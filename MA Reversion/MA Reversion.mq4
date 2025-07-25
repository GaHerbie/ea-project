//+------------------------------------------------------------------+
//|                                                       MaTest.mq4 |
//|                                  Copyright 2025, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, MetaQuotes Ltd."
#property link      "https://www.mql5.com"
#property version   "1.1"
#property strict

// 输入参数
input int BBPeriod = 30;         // 布林带时间范围
input double BBDeviation = 2.5;  // 布林带标准差倍数
input double LotSize = 0.01;     // 固定手数（最小值）
input int TimeFrame = PERIOD_M5; // 时间周期，默认5分钟
input int BaseTimeFrame = PERIOD_M5;   // 基准检查周期
input int StopLossPoints = 0;   // 固定止损点数（可选）
input int SlippagePoints = 3;   // 下单最大滑点点数
input double MiniMASpread = 300;   // 最小均值偏差点数
input double MaxMASpread = 1000;   // 最大均值偏差点数
input int ATRTimeFrame = PERIOD_M30;   // ATR时间周期
input int ATRPeriod = 240;   // ATR时间范围
input int FibonacciMaxIndex = 8;   // 斐波拉契数列最大索引
input int MASpreadFibonacciMaxIndex = 5;   // 用于价差计算的斐波拉契数列最大索引
input double TotalMaxPos = 2.0;  //最大持仓量
input int PreCloseLotMultiplier = 5;  //可提前平仓的仓位乘数
input int MagicNumber = 0;    // 用户订单标识符

// 全局变量
double ma, upperBand, lowerBand, obv, obvPrev, rsi;
double LotSize_ = LotSize;
double TimeFrame_ = TimeFrame;
//最小持仓量
double LOTSTEP = LotSize;
//最小持仓精度
double LotPrecision = 2;


// MA周期
int MA10 = 10;
int MA30 = 30;
int MA90 = 90;
int MA182 = 182;
int MA365 = 365;

double PointValue = 0.0;
datetime LastM1BarTime = 0;

//当前K线在BollingBand中的位置，
//0未知，1上穿中轨，2中轨上方，3上穿上轨，4上轨上方，
//-1下穿中轨，-2下轨下方，-3下穿下轨，-4下轨下方
int CurrentBBPos = 0;
// 当前价格相对BollingBand中轨的方向
// -1下方，1上方，0穿过
//int CurrentBBDirection = 0;

// 交易相关参数
bool CanOpenLongOrder = false;
bool CanOpenShortOrder = false;
bool CanCloseLongOrder = false;
bool CanCloseShortOrder = false;
double CloseLongDivisor = 1;
double CloseShortDivisor = 1;
bool CloseLongProfit = false;
bool CloseShortProfit = false;
int OpenLongOrderFibonacciIndex = 0;
int OpenShortOrderFibonacciIndex = 0;

// MA点差阈值
double MASpreadThreshold = MaxMASpread;

// 最后一个订单数据
int LastOpenOrderType = -1;
double LastOpenOrderPrice = -1;
double LastOpenOrderLotSize = LotSize_;
// 当前持仓量
double CurrentLongPos = 0;
double CurrentShortPos = 0;

// 用户的初始账户余额
double initialCapital = 0;

// 历史净值相关
int EquityHistoryCount = 0;
double EquityHistory[];
datetime EquityHistoryTime[];

// 默认动态数组长度
int INITIAL_ARRAY_SIZE = 1000;
// 无风险利率
double RISK_FREE_RATE = 0.01;


// 初始化
int OnInit() {
   PointValue = MarketInfo(Symbol(), MODE_POINT);
   if(PointValue == 0)
      PointValue = Point; // Fallback for brokers
      
   if (LotSize_ < MarketInfo(Symbol(), MODE_MINLOT)) {
      Print("LotSize 过小，已调整为最小值 ", MarketInfo(Symbol(), MODE_MINLOT));
      LotSize_ = MarketInfo(Symbol(), MODE_MINLOT);
   }
   // 验证时间周期有效性
   if (TimeFrame_ != PERIOD_M1 && TimeFrame_ != PERIOD_M5 && TimeFrame_ != PERIOD_M15 &&
       TimeFrame_ != PERIOD_M30 && TimeFrame_ != PERIOD_H1 && TimeFrame_ != PERIOD_H4 &&
       TimeFrame_ != PERIOD_D1 && TimeFrame_ != PERIOD_W1) {
      Print("无效时间周期，已重置为 PERIOD_M5");
      TimeFrame_ = PERIOD_M5;
   }
   
   if(OrderSelect(OrdersTotal() - 1, SELECT_BY_POS, MODE_TRADES))
   {
      if(OrderSymbol() == Symbol())
      {
         // 获取最新一个订单信息
         LastOpenOrderType = OrderType();
         LastOpenOrderPrice = OrderOpenPrice();
         LastOpenOrderLotSize = OrderLots();
      }
   }
   
   // 初始化用户本金
   initialCapital = AccountBalance();
   
   // 初始化动态数组
   //ArrayResize(EquityHistory, INITIAL_ARRAY_SIZE);
   //ArrayResize(EquityHistoryTime, INITIAL_ARRAY_SIZE);
   
   return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason) {
   if(IsTesting()) {
      CalculateSharpeRatio();
      CalculateMaxDrawdown();
      CalculateOptimalLeverage();
   }
}


// 主循环
void OnTick() {
   //--- 以M1为价格的检查周期
   datetime m1_time = iTime(NULL, BaseTimeFrame, 0);
   if(m1_time == LastM1BarTime)
      return;
   LastM1BarTime = m1_time;
   
   // 刷新MA点差阈值
   RefreshATRThreshold();
   
   // 刷新持仓数据
   RefreshPosition();
   
   // BollingBand信号
   BollingBandSignal();
   //均值回归信号
   MAReversionSignal();
   
   // 检查并开仓
   CheckAndOpenOrder();
   // 检查并平仓
   CheckAndCloseOrder();
   
   // 更新净值历史
   UpdateEquityHistory();
   
   // 在回测结束时计算夏普率
   if(IsTesting() && IsVisualMode() && EquityHistoryCount > 100) { // 确保有足够数据
      CalculateSharpeRatio();
      CalculateMaxDrawdown();
   }
   
}


// 检查开仓信号并下单
void CheckAndOpenOrder()
{  
   if (CurrentShortPos + CurrentLongPos >= TotalMaxPos){
      return;
   }

   if (CanOpenShortOrder){
      double bid = Bid;
      double stopLoss = 0.0;
      if (StopLossPoints > 0){
         stopLoss = bid + StopLossPoints * PointValue;
      }
      //Print("Open sell order, Price=", DoubleToString(bid, 2));
      double tempLotSize = CalculateLotSize(OP_SELL);
      int ticket = OrderSend(Symbol(), OP_SELL, tempLotSize, bid, SlippagePoints, stopLoss, 0, "SELL", 0, 0, clrRed);
      if(ticket < 0)
         Print("OrderSend error #", GetLastError());
         
      LastOpenOrderType = OP_SELL;
      LastOpenOrderPrice = bid;
      LastOpenOrderLotSize = tempLotSize;
   }
   if (CanOpenLongOrder){
      double ask = Ask;
      double stopLoss = 0.0;
      if (StopLossPoints > 0){
         stopLoss = ask - StopLossPoints * PointValue;
      }
      //Print("Open buy order, Price=", DoubleToString(ask, 2));
      double tempLotSize = CalculateLotSize(OP_BUY);
      int ticket = OrderSend(Symbol(), OP_BUY, tempLotSize, ask, SlippagePoints, stopLoss, 0, "BUY", 0, 0, clrGreen);
      if(ticket < 0)
         Print("OrderSend error #", GetLastError());
         
      LastOpenOrderType = OP_BUY;
      LastOpenOrderPrice = ask;
      LastOpenOrderLotSize = tempLotSize;
   }

}

// 检查平仓信号并下单
void CheckAndCloseOrder(){
   // 平空仓
   if (CanCloseShortOrder && CurrentShortPos > 0){
      double closeShortPos = 0;
      if (CurrentShortPos > LOTSTEP){
         closeShortPos = NormalizeDouble(CurrentShortPos / CloseShortDivisor, LotPrecision);
      }else{
         closeShortPos = CurrentShortPos;
      }
      for(int i = OrdersTotal() - 1; i >= 0; i--){
         if(OrderSelect(i, SELECT_BY_POS, MODE_TRADES)){
            if(OrderSymbol() == Symbol() && OrderType() == OP_SELL){
               double orderLot = OrderLots();
               if (CloseShortProfit){
                  if (OrderProfit() > 0.0){
                     OrderClose(OrderTicket(), orderLot, Ask, SlippagePoints, clrRed);
                  }
               }else if (closeShortPos > 0.0){
                  OrderClose(OrderTicket(), orderLot, Ask, SlippagePoints, clrRed);
                  if (closeShortPos > orderLot){
                     closeShortPos = closeShortPos - orderLot;
                  }else{
                     closeShortPos = 0.0;               
                  }
                  if (closeShortPos == 0.0){
                     break;
                  }
               }
               
            }
         }
      }
   }
   
   // 平多仓
   if (CanCloseLongOrder && CurrentLongPos > 0){
      double closeLongPos = 0;
      if (CurrentLongPos > LOTSTEP){
         closeLongPos = NormalizeDouble(CurrentLongPos / CloseLongDivisor, LotPrecision);
      }else{
         closeLongPos = CurrentLongPos;
      }
      for(int i = OrdersTotal() - 1; i >= 0; i--){
         if(OrderSelect(i, SELECT_BY_POS, MODE_TRADES)){
            if(OrderSymbol() == Symbol() && OrderType() == OP_BUY){
               double orderLot = OrderLots();
               if (CloseLongProfit){
                  if (OrderProfit() > 0.0){
                     OrderClose(OrderTicket(), orderLot, Bid, SlippagePoints, clrGreen);
                  }
               }else if (closeLongPos > 0.0){
                  OrderClose(OrderTicket(), orderLot, Bid, SlippagePoints, clrGreen);
                  if (closeLongPos > orderLot){
                     closeLongPos = closeLongPos - orderLot;
                  }else{
                     closeLongPos = 0.0;               
                  }
                  if (closeLongPos == 0.0){
                     break;
                  }
               }
               
            }
         }
      }
   }


}


// 基于均值回归策略判断是否开仓或平仓
void MAReversionSignal(){
   // 默认都为false
   CanOpenLongOrder = false;
   CanOpenShortOrder = false;
   CanCloseLongOrder = false;
   CanCloseShortOrder = false;
   CloseLongDivisor = 1.0;
   CloseShortDivisor = 1.0;
   CloseLongProfit = false;
   CloseShortProfit = false;

   // 布林通道中轨价格
   double centreBand = iMA(NULL, TimeFrame_, BBPeriod, 0, MODE_SMA, PRICE_CLOSE, 0);
   // 使用M1的价格
   double currentClosePrice = iClose(NULL, BaseTimeFrame, 1);
   // 当前价格与BollingBand中轨的点差
   double currentPointSpread = MathAbs(centreBand - currentClosePrice) / PointValue;
   
   // 当前无仓位
   if (LastOpenOrderType == -1) {
      if (currentPointSpread >= MASpreadThreshold){
         // 上穿上轨
         if (CurrentBBPos >= 3){
            CanOpenShortOrder = true;
         }
         // 下穿下轨
         if (CurrentBBPos <= -3){
            CanOpenLongOrder = true;
         }
      }
      
   // 已有仓位
   }else {
      // 价格处于中轨时
      if (CurrentBBPos == 1 || CurrentBBPos == -1){
         LastOpenOrderLotSize = LotSize_;
      }
      // 上穿中轨
      if (CurrentBBPos == 1 && CurrentLongPos >= (PreCloseLotMultiplier * LotSize_)){
         CanCloseLongOrder = true;
         CloseLongDivisor = 1.0;
         CloseLongProfit = true;
         OpenLongOrderFibonacciIndex = 0;
      }
      // 下穿中轨
      if (CurrentBBPos == -1 && CurrentShortPos >= (PreCloseLotMultiplier * LotSize_)){
         CanCloseShortOrder = true;
         CloseShortDivisor = 1.0;
         CloseShortProfit = true;
         OpenShortOrderFibonacciIndex = 0;
      }
      
      // 中轨上方
      if (CurrentBBPos > 1){
         if (CurrentBBPos == 2){
            // 判断是否为顶
         }
         // 上穿上轨
         if (CurrentBBPos >= 3){
            CanCloseLongOrder = true;
            CloseLongDivisor = 2.0;
            OpenLongOrderFibonacciIndex = 0;
         }
         // 当前价格与最后一单的点差
         double openOrderPointSpread = (currentClosePrice - LastOpenOrderPrice) / PointValue;
         if (LastOpenOrderType == OP_BUY && currentPointSpread >= MASpreadThreshold){
            CanOpenShortOrder = true;
         }
         double currentMASpread = MASpreadThreshold / (FibonacciValue(OpenShortOrderFibonacciIndex, 0.1) + 1);
         //Print("OpenShortOrderFibonacciIndex: ", OpenShortOrderFibonacciIndex, ", currentMASpread: ", DoubleToString(currentMASpread, 2));
         if (LastOpenOrderType == OP_SELL && openOrderPointSpread >= currentMASpread){
            CanOpenShortOrder = true;
            OpenShortOrderFibonacciIndex++;
         }
      }
      // 中轨下方
      if (CurrentBBPos < -1){
         if (CurrentBBPos == -2){
            // 判断是否为底
         }
         // 下穿下轨
         if (CurrentBBPos <= -3){
            CanCloseShortOrder = true;
            CloseShortDivisor = 2.0;
            OpenShortOrderFibonacciIndex = 0;
         }
         // 当前价格与最后一单的点差
         double openOrderPointSpread = (LastOpenOrderPrice - currentClosePrice) / PointValue;
         if (LastOpenOrderType == OP_SELL && currentPointSpread >= MASpreadThreshold){
            CanOpenLongOrder = true;
         }
         double currentMASpread = MASpreadThreshold / (FibonacciValue(OpenLongOrderFibonacciIndex, 0.1) + 1);
         //Print("OpenLongOrderFibonacciIndex: ", OpenLongOrderFibonacciIndex, ", currentMASpread: ", DoubleToString(currentMASpread, 2));
         if (LastOpenOrderType == OP_BUY && openOrderPointSpread >= currentMASpread){
            CanOpenLongOrder = true;
            OpenLongOrderFibonacciIndex++;
         }
      
      }
      
   }
   
   
}

//-- BollingBand信号
void BollingBandSignal(){
   // 布林通道中轨价格
   double centreBand = iMA(NULL, TimeFrame_, BBPeriod, 0, MODE_SMA, PRICE_CLOSE, 0);
   //计算标准差
   double std = iStdDev(NULL, TimeFrame_, BBPeriod, 0, MODE_SMA, PRICE_CLOSE, 0);
   //布林通道上下轨
   upperBand = centreBand + BBDeviation * std;
   lowerBand = centreBand - BBDeviation * std;
   // 使用M1的价格
   double currentOpenPrice = iOpen(NULL, BaseTimeFrame, 1);
   double currentClosePrice = iClose(NULL, BaseTimeFrame, 1);
   double currentHighPrice = iHigh(NULL, BaseTimeFrame, 1);
   double currentLowPrice = iLow(NULL, BaseTimeFrame, 1);
   if (currentOpenPrice < centreBand && centreBand < currentClosePrice){
      //价格上穿中轨
      CurrentBBPos = 1;
   }
   if (currentOpenPrice > centreBand && centreBand > currentClosePrice){
      //价格下穿中轨
      CurrentBBPos = -1;
   }
   if (currentOpenPrice > centreBand && centreBand < currentClosePrice
      && currentOpenPrice < upperBand && upperBand > currentClosePrice
   ) {
      // K线位于中轨上方
      CurrentBBPos = 2;
      //Print("CurrentBBPos == 2, upperBand=", DoubleToString(upperBand, 2), "currentHighPrice=", DoubleToString(currentHighPrice, 2));
   }
   if (currentOpenPrice < centreBand && centreBand > currentClosePrice
      && currentOpenPrice > lowerBand && lowerBand < currentClosePrice) {
      // K线位于中轨下方
      CurrentBBPos = -2;
      //Print("CurrentBBPos == -2, lowerBand=", DoubleToString(lowerBand, 2), "currentLowPrice=", DoubleToString(currentLowPrice, 2));
   }
   if (lowerBand > currentLowPrice) {
      //价格下穿下轨
      CurrentBBPos = -3;
      //Print("CurrentBBPos == -3, lowerBand=", DoubleToString(lowerBand, 2), "currentLowPrice=", DoubleToString(currentLowPrice, 2));
   }
   if (upperBand < currentHighPrice) {
      //价格上穿上轨
      CurrentBBPos = 3;
      //Print("CurrentBBPos == 3, upperBand=", DoubleToString(upperBand, 2), "currentHighPrice=", DoubleToString(currentHighPrice, 2));
   }
   //else{
   //   //未知
   //   CurrentBBPos = 0;
   //}
}

// 更新当前持仓量
void RefreshPosition(){
   CurrentLongPos = 0;
   CurrentShortPos = 0;
   for(int i = OrdersTotal() - 1; i >= 0; i--){
      if(OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
     {
      if(OrderSymbol() == Symbol())
        {
         // 更新持仓量
         double orderLot = OrderLots();
         if(OrderType() == OP_BUY){
            CurrentLongPos = CurrentLongPos + orderLot;
         }else if(OrderType() == OP_SELL){
            CurrentShortPos = CurrentShortPos + orderLot;
         }
        }
     }
  }


}

// 基于斐波拉契数列计算当前订单仓位
double CalculateLotSize(int orderType){
   double tempLotSize = LotSize_;
   if (LastOpenOrderType == orderType){
      double a = LotSize_;
      double b = LotSize_ + a;
      if (a == LastOpenOrderLotSize){
         tempLotSize = b;
         return tempLotSize;
      }
      if (b == LastOpenOrderLotSize){
         tempLotSize = b + a;
         return tempLotSize;
      }
      double c;
      for (int i = 2; i < FibonacciMaxIndex; i++){
         c = a + b;
         a = b;
         b = c;
         if (b == LastOpenOrderLotSize){
            tempLotSize = b + a;
            return tempLotSize;
         }else if (i == FibonacciMaxIndex-1 && b + a == LastOpenOrderLotSize){
            return LastOpenOrderLotSize;
         }
      }
   }
   
   return tempLotSize;
}

// 计算斐波拉契数列的值
double FibonacciValue(int index, double multiplier){
   double tempValue = 1.0 * multiplier;
   double a = tempValue;
   double b = tempValue + a;
   if (index == 0){
      tempValue = a;
      return tempValue;
   }
   if (index == 1){
      tempValue = b;
      return tempValue;
   }
   double c;
   for (int i = 1; i < MASpreadFibonacciMaxIndex; i++){
      c = a + b;
      a = b;
      b = c;
      if (i == index){
         tempValue = c;
         return tempValue;
      }
   }
   if (index >= MASpreadFibonacciMaxIndex){
      tempValue = c;
      return tempValue;
   }
   return tempValue;
}

// 根据ATR刷新MA点差阈值
void RefreshATRThreshold(){
   //获取波动阈值
   double atr = iATR(NULL, ATRTimeFrame, ATRPeriod, 1);
   double atrThreshold = atr / PointValue;
   if (atrThreshold > MaxMASpread){
      atrThreshold = MaxMASpread;
   }else if (atrThreshold < MiniMASpread){
      atrThreshold = MiniMASpread;
   }
   
   MASpreadThreshold = atrThreshold;
}


// 计算夏普率
double CalculateSharpeRatio() {
   int totalTrades = 0;
   double totalProfit = 0.0;
   double weeklyProfits[]; // 存储每周的收益
   ArrayResize(weeklyProfits, INITIAL_ARRAY_SIZE);
   double weeklyProfitRate[]; // 存储每周收益率
   ArrayResize(weeklyProfitRate, INITIAL_ARRAY_SIZE);
   datetime firstCloseTime = 0; // 第一笔订单的关闭时间
   int totalWeeks = 0;   // 交易总周数
   
   // 遍历历史订单
   for(int i = 0; i < OrdersHistoryTotal(); i++) {
      if(OrderSelect(i, SELECT_BY_POS, MODE_HISTORY)) {
         if(OrderSymbol() == Symbol() && OrderMagicNumber() == MagicNumber) { // 过滤 EA 交易
            totalTrades++;
            totalProfit += OrderProfit();
            datetime closeTime = OrderCloseTime();
            // 计算周索引（基于第一笔订单的绝对时间差）
            if(i == 0) {
               firstCloseTime = closeTime; // 记录第一笔订单时间
            }
            int weekIndex = (int)((closeTime - firstCloseTime) / 604800); // 604800 秒 = 1 周
            weeklyProfits[weekIndex] += OrderProfit();
            totalWeeks = MathMax(totalWeeks, weekIndex + 1); // 更新总周数
         }
      }
   }

   if(totalWeeks == 0 || initialCapital == 0) return 0.0;
   // 调整数组大小
   ArrayResize(weeklyProfits, totalWeeks);
   
   // 计算每周收益率
   int validWeeks = 0;
   for(int i = 0; i < (int)totalWeeks; i++) {
      if(weeklyProfits[i] != 0.0) { // 仅考虑有交易的周
         weeklyProfitRate[validWeeks++] = weeklyProfits[i] / initialCapital;
      }
   }
   ArrayResize(weeklyProfitRate, validWeeks);
   
   // 计算平均每周收益率
   double meanWeeklyRate = 0.0;
   for(int i = 0; i < validWeeks; i++) {
      meanWeeklyRate += weeklyProfitRate[i];
   }
   meanWeeklyRate /= validWeeks;
   
   // 计算收益率标准差
   double variance = 0.0;
   for(int i = 0; i < validWeeks; i++) {
      variance += MathPow(weeklyProfitRate[i] - meanWeeklyRate, 2);
   }
   variance /= validWeeks;
   // 每周收益率标准差
   double weeklyStdDev = MathSqrt(variance);
   
   // 52周 年化收益率
   double annualizedProfitRate = meanWeeklyRate * 52.0;
   // 52周 年化标准差
   double annualizedStdDev = weeklyStdDev * MathSqrt(52.0);
   double sharpeRatio = (annualizedProfitRate - RISK_FREE_RATE) / annualizedStdDev;
   
   Print("夏普率: ", DoubleToString(sharpeRatio * 100, 2), "% ");
   Print("年化收益率: ", DoubleToString(annualizedProfitRate * 100, 2), "% , 当前总收益: ", DoubleToString(totalProfit, 2));
   Print("交易周数: ", DoubleToString(validWeeks, 2), ", 平均每周收益率: ", DoubleToString(meanWeeklyRate * 100, 2), "% ");
   Print("每周收益标准差：", DoubleToString(weeklyStdDev, 2), ", 年化收益标准差：", DoubleToString(annualizedStdDev, 2));

   return sharpeRatio;
}

// 更新净值历史
void UpdateEquityHistory(){
   if (EquityHistoryCount % INITIAL_ARRAY_SIZE == 0){
      ArrayResize(EquityHistory, EquityHistoryCount + INITIAL_ARRAY_SIZE);
      ArrayResize(EquityHistoryTime, EquityHistoryCount + INITIAL_ARRAY_SIZE);
   }
   EquityHistory[EquityHistoryCount] = AccountEquity();
   EquityHistoryTime[EquityHistoryCount] = TimeCurrent();
   EquityHistoryCount++;
}

// 计算最大回撤
double CalculateMaxDrawdown() {
   // 初始最高净值
   double maxEquity = initialCapital;
   datetime maxEquityTime = 0;
   double maxDrawdown = 0.0;
   double maxDrawdownEquity = 0.0;
   datetime maxDrawdownTime = 0;
   double maxDrawdownMaxEquity = 0.0;
   datetime maxDrawdownMaxEquityTime = 0;

   // 遍历净值历史
   for(int i = 1; i < EquityHistoryCount; i++) {
      if(EquityHistory[i] > maxEquity) {
         maxEquity = EquityHistory[i]; // 更新高峰
         maxEquityTime = EquityHistoryTime[i];
      }else{
         double drawdown = (maxEquity - EquityHistory[i]) / maxEquity;
         if(drawdown > maxDrawdown) {
            maxDrawdown = drawdown;
            maxDrawdownEquity = EquityHistory[i];
            maxDrawdownTime = EquityHistoryTime[i];
            
            maxDrawdownMaxEquity = maxEquity;
            maxDrawdownMaxEquityTime = maxEquityTime;
         }
      }
   }

   Print("最大回撤比率: ", DoubleToString(maxDrawdown * 100, 2), "%, ");
   Print("最大回撤前的最大净值: ", DoubleToString(maxDrawdownMaxEquity, 2), ", ");
   Print("最大回撤前的最大净值时间: ", maxDrawdownMaxEquityTime, ", ");
   Print("最大回撤时的净值: ", DoubleToString(maxDrawdownEquity, 2), ", ");
   Print("最大回撤时的净值时间: ", maxDrawdownTime, ", ");
   return maxDrawdown;
}


// 计算最优杠杆比率 using Kelly Criterion
double CalculateOptimalLeverage() {
   int totalTrades = 0;
   int winningTrades = 0;
   double totalProfit = 0.0;
   double totalLoss = 0.0;
   double maxProfit = 0.0;
   double maxLoss = 0.0;

   // 遍历历史订单
   for(int i = 0; i < OrdersHistoryTotal(); i++) {
      if(OrderSelect(i, SELECT_BY_POS, MODE_HISTORY)) {
         if(OrderSymbol() == Symbol() && OrderMagicNumber() == MagicNumber) {
            totalTrades++;
            double profit = OrderProfit();
            if(profit > 0) {
               winningTrades++;
               totalProfit += profit;
               maxProfit = MathMax(maxProfit, profit);
            } else {
               totalLoss += MathAbs(profit);
               maxLoss = MathMax(maxLoss, MathAbs(profit));
            }
         }
      }
   }

   if(totalTrades == 0 || winningTrades == 0 || totalLoss == 0) return 0.0; // 避免除零

   // 计算胜率 W
   double winRate = (double)winningTrades / totalTrades;

   // 计算盈亏比 R (平均盈利 / 平均亏损)
   double avgProfit = totalProfit / winningTrades;
   double avgLoss = totalLoss / (totalTrades - winningTrades);
   double riskRewardRatio = avgProfit / avgLoss;

   // 计算凯利百分比
   double kellyPercent = winRate - ((1 - winRate) / riskRewardRatio);
   if(kellyPercent < 0) kellyPercent = 0.0; // 负值无效，设为 0

   // 最大预期亏损
   double maxLossPercent = maxLoss / initialCapital;
   // 完整凯利杠杆
   double fullLeverage = kellyPercent / maxLossPercent; 

   // 半凯利降低风险
   double halfKellyLeverage = fullLeverage / 2.0;

   // 输出结果
   Print("胜率: ", DoubleToString(winRate * 100, 2), "%");
   Print("盈亏比 R: ", DoubleToString(riskRewardRatio * 100, 2), "%");
   Print("最大预期亏损率: ", DoubleToString(maxLossPercent * 100, 2), "%");
   Print("凯利百分比: ", DoubleToString(kellyPercent * 100, 2), "%");
   Print("完整凯利杠杆: ", DoubleToString(fullLeverage, 2));
   Print("半凯利杠杆: ", DoubleToString(halfKellyLeverage, 2));

   // 返回半凯利杠杆作为推荐值
   return halfKellyLeverage;
}

//+------------------------------------------------------------------+
//|                                                       MaTest.mq4 |
//|                                  Copyright 2025, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, MetaQuotes Ltd."
#property link      "https://www.mql5.com"
#property version   "1.00"
#property strict


// --- 输入参数
// 默认订单成交量
input double LotSize = 0.01;
// 时间周期，默认5分钟
input int TimeFrame = PERIOD_M5;
// 波动K线数
input int VolatilityBars = 10;
// 波动阈值（点）
input double VolatilityThreshold = 800.0;
// 信号强度阈值0-100
input double TotalSignalThreshold = 4;

input int StopLossPoints = 100;  // 固定止损点数（可选）

input double TrendThreshold = 500.0;   // 趋势反转阈值（点数）

// 全局变量
double PointValue = 0.0;
double LotSize_ = LotSize;
double TimeFrame_ = TimeFrame;
datetime lastBarTime = 0;

// 成交量信号倍数
double VolumeMultiplierSignal = 1;
// 成交量信号依赖的K线数
int VolumePreBars = 5;
// 价格的趋势，1向上，0中性，-1向下
int PriceTrend = 0;

// MA周期
int MA10 = 10;
int MA30 = 30;
int MA90 = 90;
int MA182 = 182;
int MA365 = 365;

// 平仓价格差距比率阈值
double PriceChangeRateThreshold = 0.6;
int OrderCloseTimeThreshold = 120;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
  {
   PointValue = MarketInfo(Symbol(), MODE_POINT);
   if(PointValue == 0)
      PointValue = Point; // Fallback for brokers
   return(INIT_SUCCEEDED);
  }


//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
  {
//--- Check for new M1 bar
   static datetime lastBarTime = 0;
   datetime m1_time = iTime(NULL, TimeFrame_, 0);
   if(m1_time == lastBarTime)
      return;
   lastBarTime = m1_time;

// 检查当前是否存在仓位
   //if(OrdersTotal() == 0)
   //  {
   //   checkAndCreateOrderSignal();
   //  }
   //else
   //  {
   //   checkAndCloseOrderSignal();
   //  }
   
   // 趋势识别
   IdentifyTrend2();

  }
//+------------------------------------------------------------------+

// 检查入场信号并下单
void checkAndCreateOrderSignal()
  {
// 检查M1价格变化
   double priceChange = checkPriceChange();
   if(PriceTrend == 0 || priceChange == 0)
     {
      // 价格趋势不明
      return;
     }

   double ma_signal = checkMASignal();
   double volume_signal = checkVolumeSignal();
   double pin_bar_signal = checkPinBar();

   string signal_text = "";
   double total_signal = 0.0;
   if(PriceTrend == 1)
     {
      // 上升趋势，检查顶部信号
      total_signal = ma_signal + volume_signal - pin_bar_signal;
      if(total_signal > TotalSignalThreshold)
        {
         StringAdd(signal_text, "超短线上涨趋势顶部信号，");
         // 创建一个向下箭头
         string arrowName = "Arrow_" + TimeToString(iTime(NULL, TimeFrame_, 1));
         if(ObjectCreate(arrowName, OBJ_ARROW_DOWN, 0, iTime(NULL, TimeFrame_, 1), iHigh(NULL, TimeFrame_, 1) + 150 * Point)) {
            ObjectSet(arrowName, OBJPROP_COLOR, clrDeepSkyBlue);
            ObjectSet(arrowName, OBJPROP_WIDTH, 3);
            //ObjectSet(arrowName, OBJPROP_TIMEFRAMES, OBJ_ALL_PERIODS); // 所有时间框架可见
         }
        }
     }
   else
     {
      // 下降趋势，检查底部信号
      total_signal = ma_signal + volume_signal + pin_bar_signal;
      if(total_signal > TotalSignalThreshold)
        {
         StringAdd(signal_text, "超短线下跌趋势底部信号，");
         // 创建一个向上箭头
         string arrowName = "Arrow_" + TimeToString(iTime(NULL, TimeFrame_, 1));
         if(ObjectCreate(arrowName, OBJ_ARROW_UP, 0, iTime(NULL, TimeFrame_, 1), iLow(NULL, TimeFrame_, 1) - 10 * Point)) {
            ObjectSet(arrowName, OBJPROP_COLOR, clrDeepSkyBlue);
            ObjectSet(arrowName, OBJPROP_WIDTH, 3);
            //ObjectSet(arrowName, OBJPROP_TIMEFRAMES, OBJ_ALL_PERIODS); // 所有时间框架可见
         }
        }
     }

   if(StringLen(signal_text) > 0)
     {
      Print(signal_text, ", 价格差：", DoubleToString(priceChange, 2),
            ", 信号强度：", DoubleToString(total_signal, 2), ", MA信号强度：", DoubleToString(ma_signal, 2),
            ", Volume信号强度：", DoubleToString(volume_signal, 2), ", PinBar信号强度：", DoubleToString(pin_bar_signal, 2)
           );
     }

  }

// 检查出场信号并平仓
void checkAndCloseOrderSignal()
  {
   for(int i = OrdersTotal() - 1; i >= 0; i--)
     {
      if(OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
        {
         // 刷新市场价格
         //RefreshRates();
         if(OrderSymbol() == Symbol())
           {
            datetime orderOpenTime = OrderOpenTime();
            datetime currentTime = TimeCurrent();
            if (currentTime < orderOpenTime + OrderCloseTimeThreshold){
               continue;
            }
            
            double orderOpenPrice = OrderOpenPrice();
            string orderData = OrderComment();
            string priceChangeStr = splitStringByIndex(orderData, "|", 1);
            double priceChange = 0;
            if(StringLen(priceChangeStr) == 0)
              {
               priceChange = StringToDouble(priceChangeStr);
              }
            double currentPrice = iClose(NULL, TimeFrame_, 0);
            string signal_text = "";

            double priceChangeRate = checkOrderPriceChangeRate(orderOpenPrice, currentPrice, orderData);
            if(priceChangeRate >= PriceChangeRateThreshold)
              {
               StringAdd(signal_text, "价格变化率达到阈值，可平仓，变化率：");
               StringAdd(signal_text, DoubleToString(priceChangeRate, 2));
               if(OrderType() == OP_BUY)
                 {
                  OrderClose(OrderTicket(), LotSize_, Bid, 10, clrGreen);
                 }
               else
                  if(OrderType() == OP_SELL)
                    {
                     OrderClose(OrderTicket(), LotSize_, Ask, 10, clrRed);
                    }
               Print(signal_text);
               continue;
              }

            double ma_signal = checkMASignal();
            double volume_signal = checkVolumeSignal();
            double pin_bar_signal = checkPinBar();
            double total_signal = 0.0;
            if(OrderType() == OP_BUY)
              {
               // 买单，检查顶部信号
               total_signal = ma_signal + volume_signal - pin_bar_signal;
               if(total_signal > TotalSignalThreshold)
                 {
                  StringAdd(signal_text, "买单顶部信号，");
                  OrderClose(OrderTicket(), LotSize_, Bid, 50, clrGreen);
                 }

              }
            else
               if(OrderType() == OP_SELL)
                 {
                  // 卖单，检查底部信号
                  total_signal = ma_signal + volume_signal + pin_bar_signal;
                  if(total_signal > TotalSignalThreshold)
                    {
                     StringAdd(signal_text, "卖单底部信号，");
                     OrderClose(OrderTicket(), LotSize_, Bid, 50, clrGreen);
                    }
                 }
                 
            if(StringLen(signal_text) > 0)
              {
               Print(signal_text, ", 价格变化率：", DoubleToString(priceChangeRate, 2),
                     ", 信号强度：", DoubleToString(total_signal, 2), ", MA信号强度：", DoubleToString(ma_signal, 2),
                     ", Volume信号强度：", DoubleToString(volume_signal, 2), ", PinBar信号强度：", DoubleToString(pin_bar_signal, 2)
                    );
              }

           }
        }
     }
  }


// 检查M1超短线价格变化
double checkPriceChange()
  {
   int highest_index = iHighest(NULL, TimeFrame_, MODE_CLOSE, VolatilityBars, 2);
   double highest = iHigh(NULL, TimeFrame_, highest_index);
   int lowest_index = iLowest(NULL, TimeFrame_, MODE_CLOSE, VolatilityBars, 2);
   double lowest = iLow(NULL, TimeFrame_, lowest_index);
   double close = iClose(NULL, TimeFrame_, 1);
   double downPrice = MathAbs(highest - close);
   double upperPrice = MathAbs(close - lowest);

   double priceChange = 0.0;
   if(downPrice > upperPrice * 2 && downPrice / PointValue > VolatilityThreshold)
     {
      // 价格趋势向下
      PriceTrend = -1;
      priceChange = downPrice;
     }
   else
      if(upperPrice > downPrice * 2 && upperPrice / PointValue > VolatilityThreshold)
        {
         // 价格趋势向上
         PriceTrend = 1;
         priceChange = upperPrice;
        }
      else
        {
         // 价格趋势不明显
         PriceTrend = 0;
        }

   return priceChange;
  }

// 计算MA信号强度
double checkMASignal()
  {
   double ma_signal_m1 = getMASignalByTF(PERIOD_M1, 1);
   double ma_signal_m5 = getMASignalByTF(PERIOD_M5, 1.1);
   double ma_signal_m15 = getMASignalByTF(PERIOD_M15, 1.2);
   double ma_signal_m30 = getMASignalByTF(PERIOD_M30, 1.3);
   double ma_signal_h1 = getMASignalByTF(PERIOD_H1, 1.4);

   double total_ma_signal = ma_signal_m1 + ma_signal_m5 + ma_signal_m15 + ma_signal_m30 + ma_signal_h1;
   return total_ma_signal;
  }

// 获取指定周期的MA信号强度
double getMASignalByTF(ENUM_TIMEFRAMES timeframe, double multiplierSignal)
  {
   double openPrice  = iOpen(NULL, timeframe, 1);
   double closePrice = iClose(NULL, timeframe, 1);
   double highPrice  = iHigh(NULL, timeframe, 1);
   double lowPrice   = iLow(NULL, timeframe, 1);

//double ma10_tf = iMA(NULL, timeframe, MA10, 0, MODE_SMA, PRICE_CLOSE, 1);
   double ma30_tf = iMA(NULL, timeframe, MA30, 0, MODE_SMA, PRICE_CLOSE, 1);
   double ma90_tf = iMA(NULL, timeframe, MA90, 0, MODE_SMA, PRICE_CLOSE, 1);
   double ma182_tf = iMA(NULL, timeframe, MA182, 0, MODE_SMA, PRICE_CLOSE, 1);
   double ma365_tf = iMA(NULL, timeframe, MA365, 0, MODE_SMA, PRICE_CLOSE, 1);

// 计算MA信号强度
   double ma_signal = 0.0;
   if(highPrice > ma30_tf && lowPrice < ma30_tf)
     {
      ma_signal += 1;
     }
   if(highPrice > ma90_tf && lowPrice < ma90_tf)
     {
      ma_signal += 1;
     }
   if(highPrice > ma182_tf && lowPrice < ma182_tf)
     {
      ma_signal += 1;
     }
   if(highPrice > ma365_tf && lowPrice < ma365_tf)
     {
      ma_signal += 1;
     }
   return ma_signal * multiplierSignal;
  }

// 计算成交量信号强度
double checkVolumeSignal()
  {
   double sum = 0;
   for(int i = 2; i <= VolumePreBars+1; i++)
      sum += iVolume(NULL, TimeFrame_, i);
   double avgVolume = sum / VolumePreBars;
   double currentVolume = iVolume(NULL, TimeFrame_, 1);

   double volume_signal = 0.0;
   if(currentVolume > avgVolume)
     {
      volume_signal = currentVolume / avgVolume * VolumeMultiplierSignal;
     }
   return volume_signal;
  }

// 根据趋势方向检测上/下影线 信号
double checkPinBar()
  {
   double pin_bar_signal = 0.0;
   double open = iOpen(NULL, TimeFrame_, 0);
   double close = iClose(NULL, TimeFrame_, 0);
   double high = iHigh(NULL, TimeFrame_, 0);
   double low = iLow(NULL, TimeFrame_, 0);
   double body = MathAbs(open - close);
   double upperWick = high - MathMax(open, close);
   double lowerWick = MathMin(open, close) - low;


   if(upperWick > lowerWick && upperWick >= body * 2 && body > 0)
     {
      // 上影线看空
      pin_bar_signal -= 1;
      if(open > close)
        {
         pin_bar_signal -= 1;
        }
     }
   else
      if(lowerWick > upperWick && lowerWick >= body * 2 && body > 0)
        {
         // 下影线看多
         pin_bar_signal += 1;
         if(open < close)
           {
            pin_bar_signal += 1;
           }
        }

   return pin_bar_signal;
  }
//+------------------------------------------------------------------+


// 检查M1超短线价格变化
double checkOrderPriceChangeRate(double orderOpenPrice, double currentPrice, string orderData)
  {
   double priceChangeRate = 0;
   string priceChangeStr = splitStringByIndex(orderData, "|", 1);
   double priceChange = 0;
   if(StringLen(priceChangeStr) == 0)
     {
      priceChange = StringToDouble(priceChangeStr);
     }
   if(priceChange == 0)
     {
      return priceChangeRate;
     }

   string oldPriceTrendStr = splitStringByIndex(orderData, "|", 0);
   double oldPriceTrend = 0;
   if(StringLen(oldPriceTrendStr) == 0)
     {
      oldPriceTrend = StringToInteger(oldPriceTrendStr);
     }

   if(oldPriceTrend == 1)
     {
      priceChangeRate = (orderOpenPrice - currentPrice) / priceChange;
     }
   else
      if(oldPriceTrend == -1)
        {
         priceChangeRate = (currentPrice - orderOpenPrice) / priceChange;
        }
   return priceChangeRate;
  }


// 生成订单数据
string generateOrderData(int PriceTrend, double priceChange, double totalSignal)
  {
   string orderData = "";
   if(PriceTrend == 1)
     {
      orderData += "Short selling";
     }
   else
      if(PriceTrend == -1)
        {
         orderData += "Long buying";
        }
   orderData += "|"+IntegerToString(PriceTrend);
   orderData += "|"+DoubleToString(priceChange);
   orderData += "|"+DoubleToString(totalSignal);

   return orderData;
  }

// 分割并获取字符串中的子字符串
string splitStringByIndex(string source, string delimiter, int index)
  {
   int count = 0;
   int pos = 0;
   int len = StringLen(source);

   string subString = "";
   while(pos < len)
     {
      int nextPos = StringFind(source, delimiter, pos);
      if(nextPos == -1)
         nextPos = len;

      int subLen = nextPos - pos;
      if(subLen > 0)
        {
         string subStr = StringSubstr(source, pos, subLen);
         if(count == index)
           {
            subString = subStr;
            break;
           }
         count++;
        }

      pos = nextPos + StringLen(delimiter);
     }

   return subString;
  }
//+------------------------------------------------------------------+

// 当前趋势方向：1向上，0中性，-1向下
int CurrentTrendDirect = 0;
// 当前趋势开始时间
datetime CurrentTrendStartTime = 0;
// 当前趋势开始价格
double CurrentTrendStartPrice = 0;
// 当前趋势最高/低价格
double CurrentTrendTopPrice = 0;
// 基于TimeFrame_识别短线趋势起点
void IdentifyTrend(){
   // 获取 tf MA10
   double ma10 = iMA(NULL, TimeFrame_, 10, 0, MODE_SMA, PRICE_CLOSE, 1);
   double tfClose = iClose(NULL, TimeFrame_, 1);
   double tfOpen = iOpen(NULL, TimeFrame_, 1);
   
   int tempTrendDirect = CurrentTrendDirect;
   if (tfClose < ma10 && tfOpen < ma10){
      // 下跌趋势
      tempTrendDirect = -1;
   }
   if (tfClose > ma10 && tfOpen > ma10){
      // 上涨趋势
      tempTrendDirect = 1;
   }
   
   int startIndex = 0;
   double maxPrice = tfClose;
   double minPrice = tfClose;
   
   // 逆向查找起点
   for(int i = 2; i <= 120; i++) {
      double tfClose_i = iClose(NULL, TimeFrame_, i);
      double tfHigh_i = iHigh(NULL, TimeFrame_, i);
      double tfLow_i = iLow(NULL, TimeFrame_, i);
      double ma10_i = iMA(NULL, TimeFrame_, 10, 0, MODE_SMA, PRICE_CLOSE, i);
      
      // 下跌趋势
      if(tempTrendDirect == -1 && tfClose_i > ma10_i){
         double high_i = iHigh(NULL, TimeFrame_, i);
         if (high_i > maxPrice){
            maxPrice = high_i;
            startIndex = i;
         }
         double priceSpread = maxPrice - tfClose_i;
         if (priceSpread / PointValue > TrendThreshold){
            break;
         }
      
      }
      
      if(tempTrendDirect == 1 && tfClose_i < ma10_i){
         double low_i = iLow(NULL, TimeFrame_, i);
         if (low_i < minPrice){
            minPrice = low_i;
            startIndex = i;
         }
         double priceSpread = tfClose_i - minPrice;
         if (priceSpread / PointValue > TrendThreshold){
            break;
         }
      }
   }

   if(startIndex > 0) {
      datetime startTime = iTime(NULL, TimeFrame_, startIndex);
      double startPrice = iClose(NULL, TimeFrame_, startIndex);
      double highestPrice = iHigh(NULL, TimeFrame_, startIndex);
      double lowestPrice = iLow(NULL, TimeFrame_, startIndex);
      
      double priceSpread = MathAbs(startPrice - tfClose);
      if (priceSpread / PointValue < TrendThreshold){
         return;
      }
      
      if (CurrentTrendStartTime == startTime){
         if (tempTrendDirect == -1 && tfClose < CurrentTrendTopPrice) {
            CurrentTrendTopPrice = tfClose;
         }else if (tempTrendDirect == 1 && tfClose > CurrentTrendTopPrice){
            CurrentTrendTopPrice = tfClose;
         }
         return;
      }else{
         CurrentTrendDirect = tempTrendDirect;
         CurrentTrendStartTime = startTime;
         CurrentTrendStartPrice = startPrice;
         CurrentTrendTopPrice = startPrice;
      }

      Print("Trend Start: Time=", TimeToString(startTime), " Price=", startPrice);
      if(CurrentTrendDirect == -1) Print("Highest: ", highestPrice);
      if(CurrentTrendDirect == 1) Print("Lowest: ", lowestPrice);

      // 绘制最高点（下跌趋势）
      if(CurrentTrendDirect == -1) {
         string startArrow = "Start_" + TimeToString(startTime);
         if(ObjectCreate(startArrow, OBJ_ARROW_DOWN, 0, startTime, highestPrice + 150 * Point)) {
            ObjectSet(startArrow, OBJPROP_COLOR, clrRed);
            ObjectSet(startArrow, OBJPROP_WIDTH, 3);
         }
      }

      // 绘制最低点（上涨趋势）
      if(CurrentTrendDirect == 1) {
         string startArrow = "Start_" + TimeToString(startTime);
         if(ObjectCreate(startArrow, OBJ_ARROW_UP, 0, startTime, lowestPrice - 10 * Point)) {
            ObjectSet(startArrow, OBJPROP_COLOR, clrGreen);
            ObjectSet(startArrow, OBJPROP_WIDTH, 3);
         }
      }
   }

}

// 上一轮趋势开始时间
datetime LastTrendStartTime = 0;
// 上一轮趋势开始价格
double LastTrendStartPrice = 0;
// 上一轮趋势结束时间
datetime LastTrendStopTime = 0;
// 上一轮趋势结束价格
double LastTrendStopPrice = 0;
// 上一轮趋势的方向
int LastTrendDirect = 0;
// 基于TimeFrame_记录上一轮趋势的高点与低点
void IdentifyTrend2(){
   // 获取 tf MA10
   double ma10 = iMA(NULL, TimeFrame_, 10, 0, MODE_SMA, PRICE_CLOSE, 1);
   double tfClose = iClose(NULL, TimeFrame_, 1);
   double tfOpen = iOpen(NULL, TimeFrame_, 1);
   double atr = iATR(NULL, TimeFrame_, 14, 1);
   double atrThreshold = atr * 4;
   
   int tempTrendDirect = CurrentTrendDirect;
   if (tfClose < ma10){
      // 下跌趋势
      tempTrendDirect = -1;
   }
   if (tfClose > ma10){
      // 上涨趋势
      tempTrendDirect = 1;
   }
   
   int startIndex = 0;
   double maxPrice = tfClose;
   double minPrice = tfClose;
   
   // 逆向查找起点
   for(int i = 2; i <= 120; i++) {
      double tfClose_i = iClose(NULL, TimeFrame_, i);
      double tfHigh_i = iHigh(NULL, TimeFrame_, i);
      double tfLow_i = iLow(NULL, TimeFrame_, i);
      double ma10_i = iMA(NULL, TimeFrame_, 10, 0, MODE_SMA, PRICE_CLOSE, i);
      double atr_i = iATR(NULL, TimeFrame_, 14, i);
      datetime time_i = iTime(NULL, TimeFrame_, i);
      
      // 下跌趋势
      if(tempTrendDirect == -1){
         if (tfHigh_i > ma10_i && tfHigh_i > maxPrice){
            maxPrice = tfHigh_i;
            startIndex = i;
         }
         if (tfLow_i < ma10_i){
            double priceSpread = maxPrice - tfLow_i;
            if (priceSpread > atr_i * 4){
               break;
            }
         }
      }
      
      if(tempTrendDirect == 1){
         if (tfLow_i < ma10_i && tfLow_i < minPrice){
            minPrice = tfLow_i;
            startIndex = i;
         }
         if (tfHigh_i > ma10_i){
            double priceSpread = tfHigh_i - minPrice;
            if (priceSpread > atr_i * 4){
               datetime time_index = iTime(NULL, TimeFrame_, startIndex);
               //Print("time=", time_i, ", time_index=", time_index, ", priceSpread=", DoubleToString(priceSpread, 2), ", atr_i * 4=", DoubleToString(atr_i * 4, 2));
               break;
            }
         }
      }
   }

   if(startIndex > 0) {
      datetime startTime = iTime(NULL, TimeFrame_, startIndex);
      double startPrice = iClose(NULL, TimeFrame_, startIndex);
      double highestPrice = iHigh(NULL, TimeFrame_, startIndex);
      double lowestPrice = iLow(NULL, TimeFrame_, startIndex);
      
      double priceSpread = MathAbs(startPrice - tfClose);
      if (priceSpread < atrThreshold){
         return;
      }
      if (tempTrendDirect == -1 && startPrice < LastTrendStopPrice){
         return;
      }
      if (tempTrendDirect == 1 && startPrice > LastTrendStopPrice){
         return;
      }
      
      if (LastTrendStopTime == startTime){
         if (tempTrendDirect == -1 && tfClose < CurrentTrendTopPrice) {
            CurrentTrendTopPrice = tfClose;
         }else if (tempTrendDirect == 1 && tfClose > CurrentTrendTopPrice){
            CurrentTrendTopPrice = tfClose;
         }
         return;
      }else{
         LastTrendStartTime = LastTrendStopTime;
         LastTrendStartPrice = LastTrendStopPrice;
         CurrentTrendDirect = tempTrendDirect;
         LastTrendStopTime = startTime;
         LastTrendStopPrice = startPrice;
      }
      
      // 已记录上一轮趋势，则判断当前趋势与上一轮趋势方向是否一致
      if (LastTrendStartTime > 0 && LastTrendStopTime > 0){
         if (LastTrendStopPrice > LastTrendStartPrice){
            LastTrendDirect = 1;
         }else if (LastTrendStopPrice < LastTrendStartPrice){
            LastTrendDirect = -1;
         }else{
            LastTrendDirect = 0;
         }
      
      }

      Print("Trend Start: Time=", TimeToString(startTime), ", startPrice=", startPrice, ", atrThreshold: ", DoubleToString(atrThreshold, 2));
      // 绘制最高点（下跌趋势）
      if(CurrentTrendDirect == -1) {
         string startArrow = "Start_" + TimeToString(startTime);
         if(ObjectCreate(startArrow, OBJ_ARROW_DOWN, 0, startTime, highestPrice + 150 * Point)) {
            ObjectSet(startArrow, OBJPROP_COLOR, clrRed);
            ObjectSet(startArrow, OBJPROP_WIDTH, 3);
         }
      }

      // 绘制最低点（上涨趋势）
      if(CurrentTrendDirect == 1) {
         string startArrow = "Start_" + TimeToString(startTime);
         if(ObjectCreate(startArrow, OBJ_ARROW_UP, 0, startTime, lowestPrice - 10 * Point)) {
            ObjectSet(startArrow, OBJPROP_COLOR, clrGreen);
            ObjectSet(startArrow, OBJPROP_WIDTH, 3);
         }
      }
   }

}
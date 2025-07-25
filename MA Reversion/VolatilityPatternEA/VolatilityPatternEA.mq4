//+------------------------------------------------------------------+
//| VolatilityPatternEA.mq4                                          |
//+------------------------------------------------------------------+
#property copyright "Your Name"
#property link      "https://www.example.com"
#property version   "1.00"
#property strict

//--- Input parameters
input double VolatilityThreshold = 500.0; // 波动阈值（点）
input int VolatilityBars = 10;           // 波动K线数
input double VolumeMultiplierVolatility = 1.2; // 波动成交量倍数
input double VolumeMultiplierSignal = 1.5;    // 信号成交量倍数


//--- Global variables
double PointValue = 0.0;

//--- MA periods
// MA周期
int MA10 = 10;
int MA30 = 30;
int MA90 = 90;
int MA182 = 182;
int MA365 = 365;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
    PointValue = MarketInfo(Symbol(), MODE_POINT);
    if (PointValue == 0) PointValue = Point; // Fallback for brokers
    return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
    //--- Check for new bar
    static datetime lastBarTime = 0;
    datetime m1_time = iTime(NULL, PERIOD_M1, 0);
    if (m1_time == lastBarTime) return;
    lastBarTime = m1_time;

    //--- Detect volatility
    double priceChange = iClose(NULL, PERIOD_M1, 1) - iClose(NULL, PERIOD_M1, VolatilityBars + 1);
    double avgVolume = CalculateAverageVolume(VolatilityBars);
    double currentVolume = iVolume(NULL, PERIOD_M1, 1);

    if (MathAbs(priceChange) / PointValue > VolatilityThreshold && currentVolume > avgVolume * VolumeMultiplierVolatility)
    {
        if (priceChange > 0) // Upward volatility
        {
            //--- Look for sell signals
            if (DetectBearishEngulfing() || DetectTopPinBar() || DetectDoubleTop())
            {
                if (ConfirmMASell() && Volume[0] > avgVolume * VolumeMultiplierSignal)
                {
                    double stopLoss = GetStopLossSell();
                    double takeProfit = GetTakeProfitSell();
                    int ticket = OrderSend(Symbol(), OP_SELL, 0.1, Bid, 3, stopLoss, takeProfit, "Sell Signal", 0, 0, clrRed);
                    if (ticket < 0) Print("OrderSend failed with error #", GetLastError());
                }
            }
        }
        else // Downward volatility
        {
            //--- Look for buy signals
            if (DetectBullishEngulfing() || DetectBottomPinBar() || DetectDoubleBottom())
            {
                if (ConfirmMABuy() && Volume[0] > avgVolume * VolumeMultiplierSignal)
                {
                    double stopLoss = GetStopLossBuy();
                    double takeProfit = GetTakeProfitBuy();
                    int ticket = OrderSend(Symbol(), OP_BUY, 0.1, Ask, 3, stopLoss, takeProfit, "Buy Signal", 0, 0, clrGreen);
                    if (ticket < 0) Print("OrderSend failed with error #", GetLastError());
                }
            }
        }
    }
}

//+------------------------------------------------------------------+
//| Helper functions                                                 |
//+------------------------------------------------------------------+
double CalculateAverageVolume(int bars)
{
    double sum = 0;
    for (int i = 1; i <= bars; i++)
        sum += Volume[i];
    return sum / bars;
}

bool DetectBearishEngulfing()
{
    if (Close[1] > Open[1] && Open[0] > Close[1] && Close[0] < Open[1])
        return true;
    return false;
}

bool DetectTopPinBar()
{
    double body = MathAbs(Open[0] - Close[0]);
    double upperWick = High[0] - MathMax(Open[0], Close[0]);
    if (upperWick >= body * 2 && body > 0)
        return true;
    return false;
}

bool DetectDoubleTop()
{
    double high1 = High[1];
    double high2 = High[3];
    double lowBetween = MathMin(Low[1], Low[2]);
    if (MathAbs(high1 - high2) < VolatilityThreshold * PointValue * 0.2 && Close[0] < lowBetween)
        return true;
    return false;
}

bool DetectBullishEngulfing()
{
    if (Close[1] < Open[1] && Open[0] < Close[1] && Close[0] > Open[1])
        return true;
    return false;
}

bool DetectBottomPinBar()
{
    double body = MathAbs(Open[0] - Close[0]);
    double lowerWick = MathMin(Open[0], Close[0]) - Low[0];
    if (lowerWick >= body * 2 && body > 0)
        return true;
    return false;
}

bool DetectDoubleBottom()
{
    double low1 = Low[1];
    double low2 = Low[3];
    double highBetween = MathMax(High[1], High[2]);
    if (MathAbs(low1 - low2) < VolatilityThreshold * PointValue * 0.2 && Close[0] > highBetween)
        return true;
    return false;
}

bool ConfirmMASell()
{
    double ma10_m1 = iMA(NULL, PERIOD_M1, MA10, 0, MODE_SMA, PRICE_CLOSE, 0);
    double ma30_m1 = iMA(NULL, PERIOD_M1, MA30, 0, MODE_SMA, PRICE_CLOSE, 0);
    double ma90_m5 = iMA(NULL, PERIOD_M5, MA90, 0, MODE_SMA, PRICE_CLOSE, 0);
    double ma182_m15 = iMA(NULL, PERIOD_M15, MA182, 0, MODE_SMA, PRICE_CLOSE, 0);
    double ma365_m30 = iMA(NULL, PERIOD_M30, MA365, 0, MODE_SMA, PRICE_CLOSE, 0);

    if (Close[0] < ma10_m1 && Close[0] < ma30_m1 && (Close[0] < ma90_m5 || Close[0] < ma182_m15 || Close[0] < ma365_m30))
        return true;
    return false;
}

bool ConfirmMABuy()
{
    double ma10_m1 = iMA(NULL, PERIOD_M1, MA10, 0, MODE_SMA, PRICE_CLOSE, 0);
    double ma30_m1 = iMA(NULL, PERIOD_M1, MA30, 0, MODE_SMA, PRICE_CLOSE, 0);
    double ma90_m5 = iMA(NULL, PERIOD_M5, MA90, 0, MODE_SMA, PRICE_CLOSE, 0);
    double ma182_m15 = iMA(NULL, PERIOD_M15, MA182, 0, MODE_SMA, PRICE_CLOSE, 0);
    double ma365_m30 = iMA(NULL, PERIOD_M30, MA365, 0, MODE_SMA, PRICE_CLOSE, 0);

    if (Close[0] > ma10_m1 && Close[0] > ma30_m1 && (Close[0] > ma90_m5 || Close[0] > ma182_m15 || Close[0] > ma365_m30))
        return true;
    return false;
}

double GetStopLossSell()
{
    return High[0] + 10 * PointValue; // 10 points above high
}

double GetTakeProfitSell()
{
    double volatility = MathAbs(Close[0] - Close[VolatilityBars - 1]);
    return Bid - volatility * 0.5; // 50% of volatility
}

double GetStopLossBuy()
{
    return Low[0] - 10 * PointValue; // 10 points below low
}

double GetTakeProfitBuy()
{
    double volatility = MathAbs(Close[0] - Close[VolatilityBars - 1]);
    return Ask + volatility * 0.5; // 50% of volatility
}

//+------------------------------------------------------------------+
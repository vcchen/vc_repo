//+------------------------------------------------------------------+
//|                                                     FxEA_VC.mq4 |
//|                                                               VC |
//|                                                               VC |
//+------------------------------------------------------------------+
#property copyright "VC"
#property link      "VC"

#define MagicNumber 19830709

extern int StopLossPoint=200;
extern double RiskyPercentage=0.05;
extern int TrailingStop_Add=300;
extern int TrailingStop_Taken=500;
extern double TradingUnitLots=0.1;
extern int UnitPricePerLots=1000;
extern int Leverage=100;
extern int Minus=10;
extern int SecondsPerBar=900;
extern int MinimalBarsAllowClose=20;
extern int fastMAPeriod=6;
extern int slowMAPeriod=26;
extern string fileName="prevChk.log";

string preCheckedMinutes="";
int logFileWriter=-1;
int Slippage=3;

int whatlookingfor=0;

double zigzagArray[], highArray[],lowArray[];

void initSlippage(){
   Slippage=MathRound((Ask-Bid)/Point);
}

int InitLogFileWriter(){
   int handle=FileOpen("EA.log",FILE_CSV|FILE_READ|FILE_WRITE, ":");
   
   if(handle!=-1) logFileWriter=handle;
   
   return (handle);
}

void writeTimeToLog(){
   int handle=FileOpen(fileName,FILE_CSV|FILE_WRITE,";");
   
   if(handle!=-1){
      FileWrite(handle,TimeToStr(Time[0],TIME_DATE|TIME_MINUTES));
      FileClose(handle);
   }
}

string getPrevLoggedTime(){
   int handle=FileOpen(fileName,FILE_CSV|FILE_READ,";");
   
   if(handle!=-1){
      string result=FileReadString(handle);
      FileClose(handle);
      return (result);
   }else return("");
}

void WriteLogToFile(string logMessage){
   string currentTime=TimeToStr(Time[0],TIME_DATE|TIME_SECONDS);
   
   if(logFileWriter!=-1){
      FileSeek(logFileWriter, 0, SEEK_END);
      FileWrite(logFileWriter,currentTime, logMessage);
   }
}

void CloseLogFileWriter(){
   if(logFileWriter!=-1)
      FileClose(logFileWriter);
}

//+------------------------------------------------------------------+
//| check current risky fund using. 
//| if the percentage >=15%, return fase(not available to trade), 
//|     else return true, available to trade.
//+------------------------------------------------------------------+
bool CheckForRisky(double inlots=0.0){
   double pending_margin=inlots*UnitPricePerLots;
   double balance=AccountBalance();
   double margin=AccountMargin();
   double percentage=(margin+pending_margin)/balance;
   if(percentage>=RiskyPercentage)
      return (true);
   return (false);
}

//+------------------------------------------------------------------+
//| check for existing orders.
//|   1. Check for opening reversal
//|   2. Check for trailing stop 
//+------------------------------------------------------------------+
int CheckForExisting(){

   CheckOpeningReversal();

   int total=OrdersTotal();
   int ticket[100];
   
   for(int i=0;i<total;i++){
      if(OrderSelect(i,SELECT_BY_POS)==false) continue;
      ticket[i]=OrderTicket();
   }
   
   for(i=0;i<total;i++){
      if(OrderSelect(ticket[i],SELECT_BY_TICKET)==false) continue;
      
      if(OrderSymbol()==Symbol() && OrderMagicNumber()==MagicNumber){
         CheckTrailingStop();
      }
   }

   return (0);
}

//+------------------------------------------------------------------+
//| Check if the current trend is reversal with current opening. 
//| If the result is negative, close all the current opening trade.
//+------------------------------------------------------------------+
int CheckOpeningReversal(){
   GetZigZagArrays();
   
   if(zigzagArray[0]!=0){
      if(highArray[0]!=0){
         //Close all sell trade whose open price is lower than the current high price
         CloseAllWithLimit(OP_SELL,highArray[0]);
      }else{
         //Close all buy trade whose open price is higher than the current low price
         CloseAllWithLimit(OP_BUY,lowArray[0]);
      }
   }else{
      if(zigzagArray[1]!=0){
         if(highArray[1]!=0){
            //if(highArray[1]>OpenPrice) set close price of sell trade to the high price
            //else set close price to previous higher price
            ModifyAllWithLimit(OP_SELL,highArray[1]);
         }else{
            //if(lowArray[1]<OpenPrice) set close price of buy trade to the lower price 
            //else set close price to previous lower price
            ModifyAllWithLimit(OP_BUY,lowArray[1]); 
         }
      }else{
         //for those sell trades, if the close price higher than open price and 
         //    lower than previous high, set stoploss to previous high 
         //for those buy trades, if the close price lower than open price and 
         //    higher than previous low, set stoploss to previous low
         double preLowestPrice=GetPreLowestPrice();
         double preHighestPrice=GetPreHighestPrice();
         
         ModifyStoplossWithPrePrice(preHighestPrice, preLowestPrice);
      }
   }   
}

void GetZigZagArrays(){
   int i=0;
   ArrayResize(zigzagArray,100);
   ArrayResize(highArray,100);
   ArrayResize(lowArray,100);
   
   for(i=0;i<100;i++){
      ArrayInitialize(zigzagArray,0.0);
      ArrayInitialize(highArray,0.0);
      ArrayInitialize(lowArray,0.0);
   }
   
   for(i=0;i<100;i++){
      zigzagArray[i]=iCustom(NULL,0,"ZigZag",12,5,3,0,i);
      highArray[i]=iCustom(NULL,0,"ZigZag",12,5,3,1,i);
      lowArray[i]=iCustom(NULL,0,"ZigZag",12,5,3,2,i);
   }
}

void CloseAllWithLimit(int dealType,double limitPrice){
   int total=OrdersTotal();
   int ticket[100];
   for(int i=0;i<total;i++){
      if(OrderSelect(i,SELECT_BY_POS)==false) continue;
      ticket[i]=OrderTicket();
   }
   
   double price=0.0;
   if(dealType==OP_BUY){
      price=Bid;
   }
   if(dealType==OP_SELL){
      price=Ask;
   }
   
   for(i=0;i<total;i++){
      if(OrderSelect(ticket[i],SELECT_BY_TICKET)==false) continue;
      
      if(OrderSymbol()==Symbol() && OrderMagicNumber()==MagicNumber){
         
         if(OrderType()==dealType){
            bool needClose=false;
            if(dealType==OP_BUY && OrderOpenPrice()>limitPrice){
               needClose=true;
            }
            if(dealType==OP_SELL && OrderOpenPrice()<limitPrice){
               needClose=true;
            }
            
            if(needClose){
               OrderClose(OrderTicket(),OrderLots(),NormalizeDouble(price,Digits),Slippage);
            }
         }
         
         
      }
   }
}

void ModifyAllWithLimit(int dealType,double limitPrice){
   int total=OrdersTotal();
   int ticket[100];
   for(int i=0;i<total;i++){
      if(OrderSelect(i,SELECT_BY_POS)==false) continue;
      ticket[i]=OrderTicket();
   }
   
   double price=0.0;
   if(dealType==OP_BUY){
      price=Bid;
   }
   if(dealType==OP_SELL){
      price=Ask;
   }
   
   for(i=0;i<total;i++){
      if(OrderSelect(ticket[i],SELECT_BY_TICKET)==false) continue;
      
      if(OrderSymbol()==Symbol() && OrderMagicNumber()==MagicNumber){
         
         if(OrderType()==dealType){
            if(dealType==OP_BUY){
               if(OrderOpenPrice()<limitPrice){
                  //Modify Order StopLoss to Order Open Price
				      if(ComparePrice(OrderStopLoss(),OrderOpenPrice())){
				         Print("Modify order stoploss to order open price");
                     OrderModify(OrderTicket(),OrderOpenPrice(),OrderOpenPrice(),0,0, Blue);
                  }
               }else{
                  //Modify Order StopLoss to limit price
				      if(ComparePrice(OrderStopLoss(),limitPrice)){
				         Print("Modify order stoploss to limit price");
				         Print("OrderStopLoss:"+OrderStopLoss()+",LimitPrice:"+limitPrice);
                     OrderModify(OrderTicket(),OrderOpenPrice(),limitPrice,0,0, Blue); 
                  }
               }
            }
            if(dealType==OP_SELL){
               if(OrderOpenPrice()>limitPrice){
				      //Modify Order StopLoss to Order Open Price
				      if(ComparePrice(OrderStopLoss(),OrderOpenPrice())){
				         Print("Modify order stoploss to order open price");
                     OrderModify(OrderTicket(),OrderOpenPrice(),OrderOpenPrice(),0,0, Blue);
                  }
               }else{
                  //Modify Order StopLoss to limit price
				      if(ComparePrice(OrderStopLoss(),limitPrice)){
				         Print("Modify order stoploss to limit price");
				         Print("OrderStopLoss:"+OrderStopLoss()+",LimitPrice:"+limitPrice);
                     OrderModify(OrderTicket(),OrderOpenPrice(),limitPrice,0,0, Blue);
                  }
               }
            }
         }
      }
   }
}

void ModifyStoplossWithPrePrice(double preHighestPrice, double preLowestPrice){
   int total=OrdersTotal();
   int ticket[100];
   for(int i=0;i<total;i++){
      if(OrderSelect(i,SELECT_BY_POS)==false) continue;
      ticket[i]=OrderTicket();
   }
   
   for(i=0;i<total;i++){
      if(OrderSelect(ticket[i],SELECT_BY_TICKET)==false) continue;
      
      if(OrderSymbol()==Symbol() && OrderMagicNumber()==MagicNumber){
            if(OrderType()==OP_BUY){
               if(OrderOpenPrice()>Bid && Bid>preLowestPrice && preLowestPrice!=OrderStopLoss()){
                  //Modify Order StopLoss to previous Lowest Price
				      Print("Modify order stoploss to previous lowest price");
                  OrderModify(OrderTicket(),OrderOpenPrice(),preLowestPrice,0,0, Blue);
               }
            }
            if(OrderType()==OP_SELL){
               if(OrderOpenPrice()<Ask && Ask<preHighestPrice && preHighestPrice!=OrderStopLoss()){
                  //Modify Order StopLoss to previous highest price
				      Print("Modify order stoploss to previous highest price");
                  OrderModify(OrderTicket(),OrderOpenPrice(),preHighestPrice,0,0, Blue);
               }
            }
      }
   }
}

double GetPreHighestPrice(){
   for(int i=1;i<100;i++){
      if(zigzagArray[i]!=0 && highArray[i]!=0)
         return (highArray[i]);
   }
}

double GetPreLowestPrice(){
   for(int i=1;i<100;i++){
      if(zigzagArray[i]!=0 && lowArray[i]!=0)
         return (lowArray[i]);
   }
}

bool ComparePrice(double price1, double price2){
   bool isDiff=true;
   
   double result=MathAbs(price1-price2);
   
   if(NormalizeDouble(result,Digits)==0.0) isDiff=false;
   
   return (isDiff);
}

//+------------------------------------------------------------------+
//| check the trailing stop level. 
//| if the taking profit >=defined * n times, modify the current trade's trailing stop
//|     to defined level * n times, just like 30/50 level.
//+------------------------------------------------------------------+
int CheckTrailingStop(){
   int times=0;
   double modifiedPrice=0.0;
   bool result=true;
   
   switch(OrderType()){
      case OP_BUY:{
         if((Bid-OrderOpenPrice())>Point*TrailingStop_Taken){
            times=(Bid-OrderOpenPrice())/(Point*TrailingStop_Taken);
            modifiedPrice=OrderOpenPrice()+times*Point*TrailingStop_Add;
            if(modifiedPrice>OrderStopLoss()){
               Print("Modify Buy order trailing stop");
               result=OrderModify(OrderTicket(),OrderOpenPrice(),modifiedPrice,OrderTakeProfit(),0,0);
               if(!result){
                  Print("Order Modify Failed #",GetLastError());
                  return (-1);
               }
            }
         }
         
         break;
      }
      case OP_SELL:{
         if((OrderOpenPrice()-Ask)>Point*TrailingStop_Taken){
            times=(OrderOpenPrice()-Ask)/(Point*TrailingStop_Taken);
            modifiedPrice=OrderOpenPrice()-times*Point*TrailingStop_Add;
            if(modifiedPrice<OrderStopLoss()){
               Print("Modify Sell order trailing stop");
               result=OrderModify(OrderTicket(),OrderOpenPrice(),modifiedPrice,OrderTakeProfit(),0,0);
               if(!result){
                  Print("Order Modify Failed #",GetLastError());
                  return (-1);
               }
            }
         }
         break;
      }
   }
}

//+------------------------------------------------------------------+
//| Check if new open
//+------------------------------------------------------------------+
int CheckForNewOpen(){
   int tradeType;
   
   //tradeType=MACondition();
   
   //if(tradeType==OP_BUY){
   //   CloseAll(OP_BUY);
      //OpenSellTrade();
   //}
   //if(tradeType==OP_SELL){
   //   CloseAll(OP_SELL);
      //OpenBuyTrade();
   //}
   
   //tradeType=KDJCondition();
   tradeType=ZigZagCondition();
   
   if(tradeType==OP_BUY){
   //   if(iMA(Symbol(),0,slowMAPeriod,0,MODE_SMA,PRICE_CLOSE,2)>iMA(Symbol(),0,fastMAPeriod,0,MODE_LWMA,PRICE_CLOSE,2)){
         OpenBuyTrade();
   //   }
   }
   if(tradeType==OP_SELL){
   //   if(iMA(Symbol(),0,slowMAPeriod,0,MODE_SMA,PRICE_CLOSE,2)<iMA(Symbol(),0,fastMAPeriod,0,MODE_LWMA,PRICE_CLOSE,2)){
         OpenSellTrade();
   //   }
   }
    
   return (0);
}



bool IsClosable(int ticket){
   int timePassed;
   if(OrderSelect(ticket,SELECT_BY_TICKET)==true){
      timePassed=(Time[0]-OrderOpenTime())/SecondsPerBar;
      if(timePassed>MinimalBarsAllowClose)
         return (true);
   }
   return (false);
}

int ZigZagCondition(){
   bool isPreZigzagHigh=false;
   for(int i=2;i<100;i++){
      if(zigzagArray[i]!=0){
         if(highArray[i]!=0)
            isPreZigzagHigh=true;
         break;
      }
   }
   
   if(zigzagArray[1]!=0&&highArray[1]!=0){
      if(whatlookingfor==OP_BUY) return (OP_BUY);
      else{
         //whatlookingfor=OP_BUY;
         return (-1);
      }
   }
   
   if(zigzagArray[1]!=0&&lowArray[1]!=0){
      if(whatlookingfor==OP_SELL) return (OP_SELL);
      else{
         //whatlookingfor=OP_SELL;
         return (-1);
      }
   }
      
   if(zigzagArray[1]==0){
      if(isPreZigzagHigh){
         whatlookingfor=OP_SELL;
         return (OP_SELL);
      }else{
         whatlookingfor=OP_BUY;
         return (OP_SELL);
      }
   }
   
   return (-1);
}

int KDJCondition(){
   double mainKDJArray[4];
   double signalKDJArray[4];
   
   for(int i=0;i<4;i++){
      mainKDJArray[i]=0.0;
      signalKDJArray[i]=0.0;
      mainKDJArray[i]=iStochastic(NULL,0,14,8,5,MODE_SMA,0,MODE_MAIN,i);
      signalKDJArray[i]=iStochastic(NULL,0,14,8,5,MODE_SMA,0,MODE_SIGNAL,i);
   }
   
   //check if buy trade can be opened.
   //if(mainKDJArray[1]>signalKDJArray[1] && signalKDJArray[1]<20){
   //   if(mainKDJArray[2]<=signalKDJArray[2] && mainKDJArray[3]<signalKDJArray[3]){
         //Open buy trade;
   //      return (OP_BUY);
   //   }
   //}
   if(mainKDJArray[1]>=20&&mainKDJArray[2]<20){
      if(mainKDJArray[0]>20){
         return (OP_BUY);
      }
   }
   
   //check if sell trade can be opened.
   //if(mainKDJArray[1]<signalKDJArray[1] && signalKDJArray[1]>80){
   //   if(mainKDJArray[2]>=signalKDJArray[2] && mainKDJArray[3]>signalKDJArray[3]){
         //Open sell trade;
   //      return (OP_SELL);
   //   }
   //}
   if(mainKDJArray[1]<=80&&mainKDJArray[2]>80){
      if(mainKDJArray[0]<80){
         return (OP_SELL);
      }
   }
   
   return (-1);
}

int MACondition(){
   double slowerMAArray[4];
   double fasterMAArray[4];
   
   for(int i=0;i<4;i++){
      slowerMAArray[i]=0.0;
      fasterMAArray[i]=0.0;
      slowerMAArray[i]=iMA(Symbol(),0,slowMAPeriod,0,MODE_SMA,PRICE_CLOSE,i);
      fasterMAArray[i]=iMA(Symbol(),0,fastMAPeriod,0,MODE_LWMA,PRICE_CLOSE,i);
   }
   
   //check if buy trade can be closed.
   if(slowerMAArray[1]>fasterMAArray[1]){
      if(slowerMAArray[2]<=fasterMAArray[2] && slowerMAArray[3]<fasterMAArray[3]){
         //Close buy trade;
         return (OP_BUY);
      }
   }
   
   //check if sell trade can be closed.
   if(slowerMAArray[1]<fasterMAArray[1]){
      if(slowerMAArray[2]>=fasterMAArray[2] && slowerMAArray[3]>fasterMAArray[3]){
         //Close sell trade;
         return (OP_SELL);
      }
   }
   
   return (-1);
}

//+------------------------------------------------------------------+
//| Close all openning trades with given direction
//+------------------------------------------------------------------+
void CloseAll(int dealType){
   int total=OrdersTotal();
   int ticket[100];
   for(int i=0;i<total;i++){
      if(OrderSelect(i,SELECT_BY_POS)==false) continue;
      ticket[i]=OrderTicket();
   }
   
   double price=0.0;
   if(dealType==OP_BUY){
      price=Bid;
   }
   if(dealType==OP_SELL){
      price=Ask;
   }
   
   for(i=0;i<total;i++){
      if(OrderSelect(ticket[i],SELECT_BY_TICKET)==false) continue;
      
      if(OrderSymbol()==Symbol() && OrderMagicNumber()==MagicNumber){
         
         if(OrderType()==dealType && IsClosable(OrderTicket())){
            OrderClose(OrderTicket(),OrderLots(),NormalizeDouble(price,Digits),Slippage);
         }
         
      }
   }
}

//+------------------------------------------------------------------+
//| Open buy trade
//+------------------------------------------------------------------+
int OpenBuyTrade(double askPrice=0.0,double lots=0,int stoploss=0,int takeprofit=0){
   double price=askPrice;
   double tradeLots=0;
   double stopPrice=0;
   double takeProfitPrice=0;
   
   if(lots==0){
      tradeLots=TradingUnitLots;
   }else{
      tradeLots=lots;
   }
   
   bool risky=CheckForRisky(tradeLots);
   if(risky){
      Print("Margin is not enough! Stop this OP_BUY request");
      return (0);
   }
   
   if(price==0.0)
      price=Ask;
   
   if(stoploss!=0){
      stopPrice=price-stoploss*Point;
   }//else{
   //   stopPrice=GetPreLowestPrice();
   //}
   
   if(takeprofit!=0){
      takeProfitPrice=price+takeprofit*Point;
   }
   
   int ticket=OrderSend(Symbol(),OP_BUY,tradeLots,price,Slippage,stopPrice,takeProfitPrice,"",MagicNumber,0,0);
   
   if(ticket<0){
      Print("OrderSend Failed #",GetLastError());
      return(0);
   }
   
   return (ticket);
}

//+------------------------------------------------------------------+
//| Open sell trade
//+------------------------------------------------------------------+
int OpenSellTrade(double sellPrice=0.0,double lots=0,int stoploss=0,int takeprofit=0){
   double price=sellPrice;
   double tradeLots=0;
   double stopPrice=0;
   double takeProfitPrice=0;
   
   if(lots==0){
      tradeLots=TradingUnitLots;
   }else{
      tradeLots=lots;
   }
   
   bool risky=CheckForRisky(tradeLots);
   if(risky){
      Print("Margin is not enough! Stop this OP_SELL request");
      return (0);
   }
   
   if(price==0.0)
      price=Bid;
   
   if(stoploss!=0){
      stopPrice=price+stoploss*Point;
   }//else{
    //  stopPrice=GetPreHighestPrice();
   //}
   
   if(takeprofit!=0){
      takeProfitPrice=price-takeprofit*Point;
   }
   
   int ticket=OrderSend(Symbol(),OP_SELL,tradeLots,price,Slippage,stopPrice,takeProfitPrice,"",MagicNumber,0,0);
   
   if(ticket<0){
      Print("OrderSend Failed #",GetLastError());
      return(0);
   }
   
   return (ticket);
}

//+------------------------------------------------------------------+
//| expert initialization function                                   |
//+------------------------------------------------------------------+
int init()
  {
//----
   
//----
   return(0);
  }
//+------------------------------------------------------------------+
//| expert deinitialization function                                 |
//+------------------------------------------------------------------+
int deinit()
  {
//----
   
//----
   return(0);
  }
//+------------------------------------------------------------------+
//| expert start function                                            |
//+------------------------------------------------------------------+
int start()
  {
//----
   //int minutes=TimeMinute(Time[0]);
   //if(minutes==preCheckedMinutes){
   //   return (0);
   //}
   //remove when testing: preCheckedMinutes=getPrevLoggedTime();
   string minutes=TimeToStr(Time[0],TIME_DATE|TIME_MINUTES);
   if(minutes==preCheckedMinutes){
      return (0);
   }
   
   Print("Start Checking at ",TimeMonth(Time[0]),"-",TimeDay(Time[0])," ",TimeHour(Time[0]),":",TimeMinute(Time[0]));
   
   preCheckedMinutes=minutes;  //remove comment when testing: 
   
   initSlippage();
   
   InitLogFileWriter();
   
   CheckForExisting();
   
   CheckForNewOpen();
   
   //remove when testing: writeTimeToLog();
   
   CloseLogFileWriter();
//----
   return(0);
  }
//+------------------------------------------------------------------+
//+------------------------------------------------------------------+
//|                                                   EATemplate.mq4 |
//|                                                               VC |
//|                                                               VC |
//+------------------------------------------------------------------+
#property copyright "VC"
#property link      "VC"

#define MagicNumber 19830709

extern int StopLossPoint=20;
extern double RiskyPercentage=0.15;
extern int TrailingStop_Add=30;
extern int TrailingStop_Taken=50;
extern double TradingUnitLots=0.01;
extern int UnitPricePerLots=1000;
//extern int Slippage=3;

int preCheckedMinutes=0;
int logFileWriter=-1;
int Slippage=3;

void initSlippage(){
   Slippage=MathRound((Ask-Bid)/Point);
}

int InitLogFileWriter(){
   int handle=FileOpen("EA.log",FILE_CSV|FILE_READ|FILE_WRITE, ":");
   
   if(handle!=-1) logFileWriter=handle;
   
   return (handle);
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

int CheckForExisting(){
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
            
            result=OrderModify(OrderTicket(),OrderOpenPrice(),modifiedPrice,OrderTakeProfit(),0,0);
            if(!result){
               Print("Order Modify Failed #",GetLastError());
               return (-1);
            }
         }
         
         break;
      }
      case OP_SELL:{
         if((OrderOpenPrice()-Ask)>Point*TrailingStop_Taken){
            times=(OrderOpenPrice()-Ask)/(Point*TrailingStop_Taken);
            modifiedPrice=OrderOpenPrice()-times*Point*TrailingStop_Add;
            
            result=OrderModify(OrderTicket(),OrderOpenPrice(),modifiedPrice,OrderTakeProfit(),0,0);
            if(!result){
               Print("Order Modify Failed #",GetLastError());
               return (-1);
            }
         }
         break;
      }
   }
}

void CloseAll(int dealType, double price){
   int total=OrdersTotal();
   int ticket[100];
   for(int i=0;i<total;i++){
      if(OrderSelect(i,SELECT_BY_POS)==false) continue;
      ticket[i]=OrderTicket();
   }
   
   for(i=0;i<total;i++){
      if(OrderSelect(ticket[i],SELECT_BY_TICKET)==false) continue;
      
      if(OrderSymbol()==Symbol() && OrderMagicNumber()==MagicNumber){
         
         if(OrderType()==dealType){
            OrderClose(OrderTicket(),OrderLots(),NormalizeDouble(price,Digits),Slippage);
         }
         
      }
   }
}

int CheckForNewOpen(){
   //need to be specified.
   OpenBuyTrade();
   OpenSellTrade();

   return (0);
}

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
   }
   
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
   }
   
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
   int minutes=TimeMinute(Time[0]);
   if(minutes==preCheckedMinutes){
      return (0);
   }
   
   Print("Start Checking at ",TimeMonth(Time[0]),"-",TimeDay(Time[0])," ",TimeHour(Time[0]),":",TimeMinute(Time[0]));
   
   preCheckedMinutes=minutes;
   
   initSlippage();
   
   InitLogFileWriter();
   
   CheckForExisting();
   
   CheckForNewOpen();
   
   CloseLogFileWriter();
//----
   return(0);
  }
//+------------------------------------------------------------------+
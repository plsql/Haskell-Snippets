-- This script takes a Mt. Gox JSON feed of trade data, parses it, and stores it in a SQLite3 table
-- The "price" and "amount" fields of the Trade datatype aren't used; I should look into removing them
-- The next step is to use the download module and write a loop that calls this recursively as long as there is still new data
-- Current create table statement: CREATE TABLE trades (date INTEGER, price_int INTEGER, amount_int INTEGER, tid INTEGER UNIQUE NOT NULL, price_currency TEXT, item TEXT, trade_type TEXT, is_primary TEXT, properties TEXT, PRIMARY KEY(tid ASC));
{-# LANGUAGE OverloadedStrings #-}

import Data.Aeson ((.:), (.:?), decode, FromJSON(..), Value(..))
import qualified Network.Download as DL
import qualified Data.ByteString.Lazy as BL
import Control.Applicative ((<$>), (<*>))
import Database.HDBC.Sqlite3 (connectSqlite3)
import qualified Database.HDBC as DB

-- stores a trade's data
data Trade = Trade {
   date :: Int,
   price :: String,
   amount :: String,
   price_int :: String,
   amount_int :: String,
   tid :: String,
   price_currency :: String,
   item :: String,
   trade_type :: String,
   primary :: String,
   properties :: String
} deriving (Show)

-- logic for the Aeson parser of the initial data
instance FromJSON Data where
   parseJSON (Object v) = 
      Data <$>
      (v .: "result")  <*>
      (v .: "return")

-- logic for the Aeson parser of the trade data
instance FromJSON Trade where
   parseJSON (Object v) = 
      Trade <$>
      (v .: "date")             <*>
      (v .: "price")            <*>
      (v .: "amount")           <*>
      (v .: "price_int")        <*>
      (v .: "amount_int")       <*>
      (v .: "tid")              <*>
      (v .: "price_currency")   <*>
      (v .: "item")             <*>
      (v .: "trade_type")       <*>
      (v .: "primary")          <*>
      (v .: "properties")
   
-- stores the initial JSON data received
data Data = Data {
   result :: String,   -- "result" tells us whether the JSON query was successful
   trades :: [Trade]   -- "trades" contains a list of each trade's information, which is then itself parsed
} deriving (Show)

-- takes a list of trades and returns a list of lists that can be used as parameters in a SQL statement
process :: Maybe Data -> [[String]]
process Nothing = []
process (Just x) = map (\(Trade a b c d e f g h i j k) -> [(show a), d, e, f, g, h, i, j, k]) myTrades -- skips price and amount because they are large and redundant
   where myTrades = trades x

main = do
--   contents <- BL.Char8.getContents -- this line uses input file from stdin as contents, used for testing
   contents <- DL.openURI "http://data.mtgox.com/api/1/BTCUSD/trades?since=0" -- download the JSON data
   let lazyContents = either (\a -> error $ "bad URI passed to Network.Download.openURI: " ++ a) (\b -> BL.fromStrict b) contents
   let myData = decode lazyContents :: Maybe Data -- parse the JSON data
   if maybe True (\x -> result x /= "success") myData -- if the JSON query failed on their side...
      then error ("JSON download failed") -- throw an error
      else do let myTrades = process myData -- otherwise, parse the trades
              -- insert trades to database
              conn <- connectSqlite3 "trades.db"
              insert <- DB.prepare conn "INSERT INTO trades VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?);"
              DB.executeMany insert $ map (\xs -> map DB.toSql xs) myTrades
              DB.commit conn
              DB.disconnect conn

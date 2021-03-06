-- should make a text file output that stores data about the information parsed (number of blocks, number of txs, etc.)
-- should clean up the function that gets insert values
-- need to decide how to associate outputs with inputs
-- create table statement for txs: CREATE TABLE txs (txHash TEXT UNIQUE NOT NULL, time INTEGER, coinbase TEXT, inputs TEXT, outputcalls TEXT, PRIMARY KEY(txHash));
-- create table statement for outputs: CREATE TABLE outputs (txHash TEXT, n INTEGER, time INTEGER, value REAL, addresses TEXT, inputs TEXT);
-- create table statement for outputs: CREATE TABLE outputs (txHASH TEXT NOT NULL, callNum INTEGER NOT NULL, addresses TEXT NOT NULL);
{-# LANGUAGE OverloadedStrings #-}
import Data.Aeson
import qualified System.Process as Process
import qualified Data.ByteString.Lazy.UTF8 as BL
import Control.Applicative ((<$>), (<*>))
import Control.Monad (mzero)
import qualified Database.HDBC as DB
import Database.HDBC.Sqlite3 (connectSqlite3)
import Data.ByteString.Lazy (intercalate)
import qualified Data.ByteString.Lazy as BB (concat)
import Data.Maybe (fromMaybe, maybeToList, catMaybes)

type BS = BL.ByteString

data Either a b = Left a | Right b

data Block = Block {
    blockHash :: BS,
    txs :: [BS],
    prevHash :: Maybe BS
} deriving (Show)

data Tx = Tx {
    txHash  :: BS,
    inputs  :: [Input],
    outputs :: [Output],
    time    :: Int
} deriving (Show)

-- the first tx in every block is a miner reward, and therefore has
-- a coinbase but no inputHash or outputCall
data Input = Input {
    coinbase   :: Maybe BS,
    inputHash  :: Maybe BS,
    outputCall :: Maybe Int
} deriving (Show)

data Output = Output {
    value :: Double,
    callNum :: Int,
    addresses :: [BS]
} deriving (Show)


instance FromJSON Block where
    parseJSON (Object v) =
        Block <$>
        (v .: "hash") <*>
        (v .: "tx") <*>
        (v .:? "previousblockhash")
    parseJSON _ = mzero

instance FromJSON Tx where
    parseJSON (Object v) =
        Tx <$>
        (v .: "txid") <*>
        (v .: "vin") <*>
        (v .: "vout") <*>
        (v .: "time")
    parseJSON _ = mzero

instance FromJSON Input where
    parseJSON (Object v) =
        Input <$>
        (v .:? "coinbase") <*>
        (v .:? "txid") <*>
        (v .:? "vout")
    parseJSON _ = mzero

instance FromJSON Output where
    parseJSON (Object v) =
        Output <$>
        (v .: "value") <*>
        (v .: "n") <*>
        (v .: "scriptPubKey" >>= (.: "addresses"))
    parseJSON _ = mzero

-- helper function, concisely converts any showable type into a ByteString
byteString :: Show a => a -> BS
byteString = BL.fromString . show

-- gets the block associated with the supplied hash using bitcoind
getBlock :: BS -> IO (Maybe Block)
getBlock hash = do
                   let hashString = BL.toString hash
                   decode . BL.fromString <$> Process.readProcess "bitcoind" ["getblock", hashString] []

blockLoop :: BS -> IO [BS]
blockLoop hash = do
                    block <- getBlock hash
                    let blockTxs = maybe [] txs block
                        previousHash = maybe Nothing prevHash block
                    maybe (return blockTxs) (fmap (blockTxs ++) . blockLoop) previousHash

-- this is the logic used if each output is given its own row
getInsertVals :: Tx -> [[BS]]
getInsertVals tx = map (\x -> [hash, n x, txTime, txValue x, txAddresses x, txInputs]) . outputs $ tx
    where hash = txHash tx
          n = byteString . callNum
          txTime = byteString . time $ tx
          txValue = byteString . value
          txAddresses = intercalate "|" . addresses
          txInputs = intercalate "|" . map (\x -> BB.concat [fromMaybe "" $ inputHash x, " ", maybe "" byteString (outputCall x)]) . inputs $ tx

main = do
    chainHeight <- Process.readProcess "bitcoind" ["getblockcount"] []
    -- using low blockheight to make testing faster
    firstHash <- Process.readProcess "bitcoind" ["getblockhash", chainHeight] []
    blockTxs <- fmap init . blockLoop . BL.fromString $ firstHash
    writeFile "hashes.txt" (unlines . map BL.toString $ blockTxs)
    {-
    conn <- connectSqlite3 "txs.db"
    txInsert <- DB.prepare conn "INSERT INTO outputs VALUES (?, ?, ?, ?, ?, ?);"
    let insertVals = concatMap getInsertVals $ txs
    DB.executeMany txInsert $ map (map (DB.toSql . BL.toString)) insertVals
    DB.commit conn
    DB.disconnect conn -}

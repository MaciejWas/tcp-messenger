{-# LANGUAGE DeriveGeneric #-}

module TcpMsg.Data
  ( ServerOpts (..),
    PayloadSize,
    MsgId,
    Logger,
    ClientId,
    Time,
    Header (..),
    headersize,
    mkMsg
  )
where

import Data.Serialize (Serialize, encode)
import qualified Data.Text as T
import GHC.Generics (Generic)
import qualified Data.ByteString as BS

----------------------------------------------------------------------------------------------------------

headersize :: Int
headersize = 32

----------------------------------------------------------------------------------------------------------

type Logger = ((T.Text, Int) -> IO ())

type ClientId = T.Text

type Time = Int

type PayloadSize = Int

type MsgId = Int

----------------------------------------------------------------------------------------------------------

data Header = Header MsgId PayloadSize deriving (Show, Eq, Generic)

instance Serialize Header

----------------------------------------------------------------------------------------------------------

data ServerOpts = ServerOpts

mkMsg :: (Serialize a) => Int -> a -> BS.StrictByteString
mkMsg msgId payload =
  let encodedPayload = encode payload
      header = Header msgId (BS.length encodedPayload)
      encodedHeader = encode header
      paddedHeader = encodedHeader <> BS.replicate (headersize - BS.length encodedHeader) 0
   in paddedHeader <> encodedPayload
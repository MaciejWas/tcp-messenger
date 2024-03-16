{-# LANGUAGE DeriveGeneric #-}

module TcpMsg.Data
  ( ServerOpts (..),
    PayloadSize,
    Logger,
    ClientId,
    UnixMsgTime,
    Header (..),
    headersize,
    mkMsg,
    fromUnix
  )
where

import qualified Data.ByteString as BS
import Data.Serialize (Serialize, encode)
import qualified Data.Text as T
import Data.UnixTime (UnixTime (UnixTime))
import Foreign.C (CTime (CTime))
import GHC.Generics (Generic)
import GHC.Int (Int32, Int64)

----------------------------------------------------------------------------------------------------------

headersize :: Int
headersize = 32

----------------------------------------------------------------------------------------------------------

type Logger = ((T.Text, Int) -> IO ())

type ClientId = T.Text

type PayloadSize = Int

type UnixMsgTime = (Int64, Int32)

fromUnix :: UnixTime -> UnixMsgTime
fromUnix (UnixTime (CTime secs) msecs) = (secs, msecs)

----------------------------------------------------------------------------------------------------------

data Header
  = Header
      UnixMsgTime
      PayloadSize
  deriving (Show, Eq, Generic)

instance Serialize Header

----------------------------------------------------------------------------------------------------------

data ServerOpts = ServerOpts

mkMsg :: (Serialize a) => UnixMsgTime -> a -> BS.StrictByteString
mkMsg (secs, msecs) payload =
  let encodedPayload = encode payload
      header = Header (secs, msecs) (BS.length encodedPayload)
      encodedHeader = encode header
      paddedHeader = encodedHeader <> BS.replicate (headersize - BS.length encodedHeader) 0
   in paddedHeader <> encodedPayload
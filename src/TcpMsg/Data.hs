{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE NamedFieldPuns #-}

module TcpMsg.Data
  ( ClientId,
    UnixMsgTime,
    Message(Message),
    Header (..),
    headersize,
    encodeMsg,
    fromUnix,
  )
where

import qualified Data.ByteString as BS
import qualified Data.ByteString.Lazy as LBS
import Data.Serialize (Serialize, encode)
import qualified Data.Text as T
import Data.UnixTime (UnixTime (UnixTime))
import Foreign.C (CTime (CTime))
import GHC.Generics (Generic)
import GHC.Int (Int32, Int64)

----------------------------------------------------------------------------------------------------------

-- Message structure
-- HEADER (message id, data size, trunk size)
-- DATA (serialized data)
-- TRUNK (raw bytestring)

----------------------------------------------------------------------------------------------------------

headersize :: Int
headersize = 32

----------------------------------------------------------------------------------------------------------

type ClientId = T.Text

type UnixMsgTime = (Int64, Int32)

fromUnix :: UnixTime -> UnixMsgTime
fromUnix (UnixTime (CTime secs) msecs) = (secs, msecs)

----------------------------------------------------------------------------------------------------------

data Header
  = Header
      UnixMsgTime
      Int -- Size of message data
      Int64 -- Size of message trunk
  deriving (Show, Eq, Generic)

instance Serialize Header

data Message a = Message
  { msgPayload :: a,
    msgTrunk :: Maybe LBS.LazyByteString
  }

----------------------------------------------------------------------------------------------------------

encodeHeader :: Header -> BS.ByteString
encodeHeader header =
  let encodedHeader = encode header
   in encodedHeader <> BS.replicate (headersize - BS.length encodedHeader) 0

-- | Adds a header to a message and serializes it all
encodeMsg ::
  (Serialize a) =>
  UnixMsgTime ->
  Message a ->
  BS.StrictByteString
encodeMsg (secs, msecs) (Message {msgPayload, msgTrunk}) =
  let payload = encode msgPayload
      trunk = maybe mempty LBS.toStrict msgTrunk
      header =
        Header
          (secs, msecs)
          (BS.length payload)
          (maybe 0 LBS.length msgTrunk)
   in encodeHeader header
        <> payload
        <> trunk
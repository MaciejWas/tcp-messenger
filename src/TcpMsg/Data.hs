{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE NamedFieldPuns #-}

module TcpMsg.Data
  ( UnixMsgTime,
    MessageId(..),
    Message (Message),
    FullMessage (..),
    Header (..),
    headersize,
    serializeMsg,
    fromUnix,
    prepare,
    prepareWithId,
    msgId,
    setId,
    newMessageId,
  )
where

import qualified Data.ByteString as BS
import qualified Data.ByteString.Lazy as LBS
import Data.Functor ((<&>))
import Data.Hashable (Hashable)
import Data.Serialize (Serialize, encode)
import Data.UnixTime (UnixTime (UnixTime), getUnixTime)
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

-- | Unix time in seconds and milliseconds
type UnixMsgTime = (Int64, Int32)

-- | Message id is a Unix time of the message creation (not the time of the message sending)
newtype MessageId = MessageId UnixMsgTime deriving (Generic, Show, Eq)

instance Hashable MessageId

instance Serialize MessageId

fromUnix :: UnixTime -> UnixMsgTime
fromUnix (UnixTime (CTime secs) msecs) = (secs, msecs)

newMessageId :: IO MessageId
newMessageId = getUnixTime <&> (MessageId . fromUnix)

----------------------------------------------------------------------------------------------------------

data Header = Header
  { hMsgId :: MessageId,
    hPayloadSize :: Int, -- Size of message data
    hTrunkSize :: Int64 -- Size of message trunk
  }
  deriving (Generic, Show, Eq)

instance Serialize Header

----------------------------------------------------------------------------------------------------------

data Message a = Message
  { msgPayload :: a,
    msgTrunk :: Maybe LBS.LazyByteString
  }

data FullMessage a = FullMessage
  { msgHeader :: Header,
    msg :: Message a,
    payload :: BS.ByteString
  }
  deriving (Show, Eq)

----------------------------------------------------------------------------------------------------------

instance (Show a) => Show (Message a) where
  show (Message {msgPayload}) = "Message < " ++ (show msgPayload) ++ ">"

instance (Eq a) => Eq (Message a) where
  (==) msga msgb = (==) (msgPayload msga) (msgPayload msgb)

instance Functor Message where
  fmap f (Message a bs) = Message (f a) bs

----------------------------------------------------------------------------------------------------------

prepare :: (Serialize a) => Message a -> IO (FullMessage a)
prepare msg@(Message {msgPayload, msgTrunk}) = do
  msgId <- newMessageId
  let bytes = encode msgPayload
  return
    ( FullMessage
        ( Header
            msgId
            (BS.length bytes)
            (maybe 0 LBS.length msgTrunk)
        )
        msg
        (encode msgPayload)
    )

prepareWithId :: (Serialize a) => MessageId -> Message a -> FullMessage a
prepareWithId mid msg@(Message {msgPayload, msgTrunk}) =
  let bytes = encode msgPayload
   in FullMessage
        ( Header
            mid
            (BS.length bytes)
            (maybe 0 LBS.length msgTrunk)
        )
        msg
        (encode msgPayload)

----------------------------------------------------------------------------------------------------------

encodeHeader :: Header -> BS.ByteString
encodeHeader header =
  let encodedHeader = encode header
   in encodedHeader <> BS.replicate (headersize - BS.length encodedHeader) 0

----------------------------------------------------------------------------------------------------------

-- | Check if the message is already serialized, if not, serialize it
serializeMsg :: FullMessage a -> BS.ByteString
serializeMsg (FullMessage header (Message {msgTrunk}) payload) = do
  let trunk = maybe mempty LBS.toStrict msgTrunk
   in ( encodeHeader header
          <> payload
          <> trunk
      )

----------------------------------------------------------------------------------------------------------

msgId :: FullMessage a -> MessageId
msgId m = let (Header msgIdVal _ _) = msgHeader m in msgIdVal

setId :: MessageId -> FullMessage a -> FullMessage a
setId newId message =
  let newHeader = (msgHeader message) {hMsgId = newId}
   in message {msgHeader = newHeader}

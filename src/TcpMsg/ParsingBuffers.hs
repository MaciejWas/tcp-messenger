{-# LANGUAGE RankNTypes #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE AllowAmbiguousTypes #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE TypeOperators #-}

module TcpMsg.ParsingBuffers where

import qualified Data.ByteString as BS
import Data.ByteString.Lazy (LazyByteString, toStrict)
import Data.Serialize (Serialize, decode)

import TcpMsg.Data (Header(Header), headersize)
import TcpMsg.Connection (readBytes, ConnectionState (Awaiting), markState, ConcurrConn, write)
import Effectful (Eff, (:>), IOE)

import Control.Concurrent (forkIO)
----------------------------------------------------------------------------------------------------------

emptyByteString :: LazyByteString
emptyByteString = mempty

----------------------------------------------------------------------------------------------------------

parseMsg :: forall connState message es. (ConcurrConn connState es, Serialize message) => Eff es (Header, message)
parseMsg = do
  header <- parseHeader @connState
  payload <- parsePayload @connState header
  return (header, payload)

parseHeader :: forall connState es. (ConcurrConn connState es) => Eff es Header
parseHeader = newBuffer @connState headersize

parsePayload :: forall connState message es. (ConcurrConn connState es, Serialize message) => Header -> Eff es message
parsePayload (Header msgId msgSize) = newBuffer @connState msgSize

newBuffer :: forall connState message es. (ConcurrConn connState es, Serialize message) => Int -> Eff es message
newBuffer = buffer @connState emptyByteString

buffer :: forall connState message es. (ConcurrConn connState es, Serialize message) => LazyByteString -> Int -> Eff es message
buffer currBuffer remainingBytes = do
  newBytes <- readBytes @es @connState remainingBytes
  let bytesInLastMessage = BS.length newBytes
  if bytesInLastMessage >= remainingBytes
    then
      let totalMessage = toStrict currBuffer <> newBytes
          Right decoded = decode totalMessage
       in return decoded
    else
      let updatedBuffer = currBuffer <> BS.fromStrict newBytes
          updatedRemaining = remainingBytes - bytesInLastMessage
       in buffer @connState updatedBuffer updatedRemaining

----------------------------------------------------------------------------------------------------------

-- An action to be performed on a received message. It is assumed that every incoming message
-- is a serialized value of type `a`
type Action es a b = a -> Eff es b

runConn :: forall connState es a b. 
  (ConcurrConn connState es, Serialize a, Serialize b) =>
  Action es a b ->
  Eff es ()
runConn action = do
  ((Header messageId _), request) <- parseMsg @connState @a @es
  forkIO (action request >>= write @connState messageId)
  return ()
  
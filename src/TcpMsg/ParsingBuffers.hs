{-# LANGUAGE AllowAmbiguousTypes #-}
{-# LANGUAGE DataKinds #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE RankNTypes #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE TypeOperators #-}

module TcpMsg.ParsingBuffers where

import Control.Monad (void)
import qualified Data.ByteString as BS
import Data.ByteString.Lazy (LazyByteString, toStrict)
import Data.Serialize (Serialize, decode)
import Effectful (Eff, IOE, (:>))
import Effectful.Concurrent (Concurrent, forkIO)
import TcpMsg.Connection (Conn, ConnSupplier, eachConnectionDo, readBytes, write)
import TcpMsg.Data (Header (Header), headersize)

parseMsg :: forall connState message es. (Conn connState :> es, Serialize message) => Eff es (Header, message)
parseMsg = do
  header <- parseHeader @connState
  payload <- parsePayload @connState header
  return (header, payload)

parseHeader :: forall connState es. (Conn connState :> es) => Eff es Header
parseHeader = newBuffer @connState headersize

parsePayload :: forall connState message es. (Conn connState :> es, Serialize message) => Header -> Eff es message
parsePayload (Header msgId msgSize) = newBuffer @connState msgSize

newBuffer :: forall connState message es. (Conn connState :> es, Serialize message) => Int -> Eff es message
newBuffer = buffer @connState (mempty :: LazyByteString)

buffer :: forall connState message es. (Conn connState :> es, Serialize message) => LazyByteString -> Int -> Eff es message
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

-- | An action to be performed on a received message. It is assumed
-- that every incoming message is a serialized value of type `a`
type Action
  es -- Effects of the action
  a --  Incoming message type
  b --  Outgoing message type
  =
  a -> Eff es a

eachRequestDo ::
  forall connState es a b.
  ( Concurrent :> es,
    Serialize a,
    Serialize b
  ) =>
  Action (Conn connState ': es) a b ->
  Eff (Conn connState ': es) ()
eachRequestDo respond = do
  ((Header messageId _), request) <- parseMsg @connState
  inParallel (respond request >>= write @connState messageId)
  eachRequestDo @connState @es @a @b respond

----------------------------------------------------------------------------------------------------------

runServer ::
  forall connState es a b.
  ( IOE :> es,
    Concurrent :> es,
    ConnSupplier connState :> es,
    Serialize a,
    Serialize b
  ) =>
  Action (Conn connState ': es) a b ->
  Eff es ()
runServer respond =
  let respondToRequests = eachRequestDo @connState @es @a @b respond
   in eachConnectionDo (inParallel respondToRequests)

----------------------------------------------------------------------------------------------------------

inParallel :: forall es. (Concurrent :> es) => Eff es () -> Eff es ()
inParallel = void . forkIO
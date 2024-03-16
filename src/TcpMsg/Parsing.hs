{-# LANGUAGE AllowAmbiguousTypes #-}
{-# LANGUAGE DataKinds #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE RankNTypes #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE TypeOperators #-}

module TcpMsg.Parsing where

import Control.Monad (void)
import qualified Data.ByteString as BS
import Data.ByteString.Lazy (LazyByteString, toStrict)
import Data.Serialize (Serialize, decode)
import Effectful (Eff, IOE, (:>))
import Effectful.Concurrent (Concurrent, forkIO)
import TcpMsg.Effects.Connection (Conn, readBytes)
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
  newBytes <- readBytes @connState remainingBytes
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

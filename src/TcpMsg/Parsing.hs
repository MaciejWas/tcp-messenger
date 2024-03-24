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
import qualified Data.ByteString.Lazy as LBS
import Data.Serialize (Serialize, decode)
import Effectful (Eff, IOE, (:>))
import Effectful.Concurrent (Concurrent, forkIO)
import TcpMsg.Data (Header (Header), Message (Message), headersize)
import TcpMsg.Effects.Connection (Conn, readBytes)
import Effectful.Dispatch.Static (unsafeEff_)

parseMsg :: forall connState a es. (Conn connState :> es, Serialize a) => Eff es (Header, Message a)
parseMsg = do
  header <- parseHeader @connState
  payload <- parsePayload @connState header
  trunk <- parseTrunk @connState header
  return (header, Message payload trunk)

parseHeader :: forall connState es. (Conn connState :> es) => Eff es Header
parseHeader = parse @connState headersize

parsePayload :: forall connState message es. (Conn connState :> es, Serialize message) => Header -> Eff es message
parsePayload (Header _ msgSize _) = parse @connState msgSize

parseTrunk :: forall connState es. (Conn connState :> es) => Header -> Eff es (Maybe LBS.LazyByteString)
parseTrunk (Header _ _ trunkSize) = case trunkSize of
  0 -> return Nothing
  _ -> do
    buf <- buffer @connState mempty (fromIntegral trunkSize)
    return (if BS.null buf then Nothing else Just (LBS.fromStrict buf))

parse :: forall connState a es. (Conn connState :> es, Serialize a) => Int -> Eff es a
parse n = do
  buf <- buffer @connState (mempty :: LazyByteString) n
  case decode buf of
    Right val -> return val
    Left e -> error e

buffer :: forall connState es. (Conn connState :> es) => LazyByteString -> Int -> Eff es BS.ByteString
buffer currBuffer remainingBytes = do
  newBytes <- readBytes @connState remainingBytes
  let bytesInLastMessage = BS.length newBytes
  if bytesInLastMessage == remainingBytes
    then return (toStrict currBuffer <> newBytes)
    else
      let updatedBuffer = currBuffer <> BS.fromStrict newBytes
          updatedRemaining = remainingBytes - bytesInLastMessage
       in buffer @connState updatedBuffer updatedRemaining

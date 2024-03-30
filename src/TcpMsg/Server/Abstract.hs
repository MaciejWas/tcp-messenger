{-# LANGUAGE AllowAmbiguousTypes #-}
{-# LANGUAGE DataKinds #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE RankNTypes #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE TypeOperators #-}

module TcpMsg.Server.Abstract where

import Control.Monad (forever, void)
import Data.Serialize (Serialize)
import TcpMsg.Data (Header (Header), Message, headersize)
import TcpMsg.Effects.Connection (Connection, readBytes, sendMessage)
import TcpMsg.Effects.Supplier (ConnectionSupplier (finalize), eachConnectionDo)
import TcpMsg.Parsing (parseMsg)
import Control.Concurrent (forkIO)
import Data.Void (Void)
import qualified Control.Exception as E

eachRequestDo ::
  forall a b c.
  ( Serialize a,
    Serialize b
  ) =>
  Connection c ->
  (Message a -> IO (Message b)) ->
  IO ()
eachRequestDo conn respond =
  forever
    ( do
        (Header messageId _ _, msg) <- parseMsg conn
        inParallel (respond msg >>= conn `sendMessage` messageId)
    )

----------------------------------------------------------------------------------------------------------

runServer ::
  forall a b c.
  ( Serialize a,
    Serialize b
  ) =>
  ConnectionSupplier c ->
  (Message a -> IO (Message b)) ->
  IO Void
runServer supplier respond =
  E.finally
    (eachConnectionDo
      supplier
      (`eachRequestDo` respond))
    (finalize supplier)


inParallel :: IO () -> IO ()
inParallel = void . forkIO
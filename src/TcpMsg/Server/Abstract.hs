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
import TcpMsg.Effects.Connection (Conn, readBytes, sendMessage)
import TcpMsg.Effects.Logger (Logger)
import TcpMsg.Effects.Supplier (ConnSupplier, eachConnectionDo)
import TcpMsg.Parsing (parseMsg)

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
  ConnSupplier c ->
  (Message a -> IO (Message b)) ->
  IO ()
runServer supplier respond =
  eachConnectionDo
    supplier
    (`eachRequestDo` respond)


inParallel :: forall es. (Concurrent :> es) => Eff es () -> Eff es ()
inParallel = void . forkIO
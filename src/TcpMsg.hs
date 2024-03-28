{-# LANGUAGE DataKinds #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE NamedFieldPuns #-}
{-# LANGUAGE RankNTypes #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE TypeOperators #-}

module TcpMsg
  ( run, createClient, ServerSettings(..)
  )
where

import Data.Serialize (Serialize)

import Network.Socket (Socket)
import qualified TcpMsg.Client.Abstract as C (createClient)
import TcpMsg.Client.Tcp (ClientOpts, createClientConnection)
import TcpMsg.Effects.Client (Client)
import TcpMsg.Effects.Connection (Connection)

import TcpMsg.Server.Abstract (runServer)
import TcpMsg.Server.Tcp (ServerTcpSettings, defaultServerTcpSettings, createTcpConnSupplier)
import TcpMsg.Data (Message)
import Data.Void (Void)
import qualified Network.Socket as Net

data ServerSettings a b es = ServerSettings
  { tcpOpts :: ServerTcpSettings,
    action :: Message a -> IO (Message b)
  }

defaultServerSettings :: ServerSettings a a es
defaultServerSettings =
  ServerSettings
    { tcpOpts = defaultServerTcpSettings,
      action = return
    }

run ::
  forall a b es.
  ( Serialize a,
    Serialize b
  ) =>
  ServerSettings a b es ->
  IO Void
run (ServerSettings {tcpOpts, action}) = do
  connSupplier <- createTcpConnSupplier tcpOpts
  runServer connSupplier action

createClient ::
  forall a b.
  ( Serialize b
  ) =>
  ClientOpts ->
  IO (Client a b Net.Socket)
createClient opts = do
  conn <- createClientConnection opts
  C.createClient conn

{-# LANGUAGE NamedFieldPuns #-}

module TcpMsg
  ( run,
    createClient,
    ServerSettings (..),
  )
where

import Data.Serialize (Serialize)
import Data.Void (Void)
import qualified Network.Socket as Net
import qualified TcpMsg.Client.Abstract as C (Client, createClient)
import TcpMsg.Client.Tcp (ClientOpts, createClientConnection)
import TcpMsg.Data (Message)
import TcpMsg.Server.Abstract (runServer)
import TcpMsg.Server.Tcp (ServerTcpSettings, createTcpConnSupplier)

data ServerSettings a b es = ServerSettings
  { tcpOpts :: ServerTcpSettings,
    action :: Message a -> IO (Message b)
  }

run ::
  ( Serialize a,
    Serialize b
  ) =>
  ServerSettings a b es ->
  IO Void
run (ServerSettings {tcpOpts, action}) = do
  connSupplier <- createTcpConnSupplier tcpOpts
  runServer connSupplier action

createClient ::
  ( Serialize b
  ) =>
  ClientOpts ->
  IO (C.Client a b Net.Socket)
createClient opts = do
  conn <- createClientConnection opts
  C.createClient conn

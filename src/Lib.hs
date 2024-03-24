{-# LANGUAGE DataKinds #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE NamedFieldPuns #-}
{-# LANGUAGE RankNTypes #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE TypeOperators #-}

module Lib
  ( run, runClient
  )
where

import Data.Serialize (Serialize)
import Effectful (Eff, IOE, runEff, (:>))
import Effectful.Concurrent (Concurrent, runConcurrent)
import Network.Socket (Socket)
import qualified TcpMsg.Client.Abstract as C (runClient)
import TcpMsg.Client.Tcp (ClientOpts, runTcpConnection)
import TcpMsg.Effects.Client (Client)
import TcpMsg.Effects.Connection (Conn)
import TcpMsg.Server.Abstract (runServer)
import TcpMsg.Server.Tcp (ServerOpts, ServerHandle, defaultServerOpts, runTcpConnSupplier)
import TcpMsg.Data (Message)

data ServerSettings a b es = ServerSettings
  { tcpOpts :: ServerOpts,
    action :: Message a -> IO (Message b)
  }

defaultServerSettings :: ServerSettings a a es
defaultServerSettings =
  ServerSettings
    { tcpOpts = defaultServerOpts,
      action = return
    }

run ::
  forall a b es.
  ( Serialize a,
    Serialize b
  ) =>
  ServerSettings a b es ->
  IO ServerHandle
run (ServerSettings {tcpOpts, action}) = runEff (runConcurrent (runTcpConnSupplier tcpOpts (runServer @a @b @Socket action)))

runClient ::
  forall a b es.
  ( Serialize b,
    Concurrent :> es,
    IOE :> es
  ) =>
  ClientOpts ->
  Eff (Client a b ': Conn Socket ': es) () ->
  Eff es ()
runClient opts action = runTcpConnection opts (C.runClient @a @b @Socket action)

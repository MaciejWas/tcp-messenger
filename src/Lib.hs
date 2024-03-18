{-# LANGUAGE DataKinds #-}
{-# LANGUAGE NamedFieldPuns #-}
{-# LANGUAGE RankNTypes #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE TypeOperators #-}

module Lib
  (
  )
where

import Data.Serialize (Serialize)
import Effectful (Eff, runEff, (:>), IOE)
import Effectful.Concurrent (runConcurrent, Concurrent)
import Network.Socket (Socket)

import TcpMsg.Server.Abstract (runServer)
import TcpMsg.Server.Tcp (ServerHandle (ServerHandle, kill), ServerOpts (ServerOpts, port), defaultServerOpts, runTcpConnSupplier)
import TcpMsg.Client.Tcp (ClientOpts (ClientOpts, serverHost, serverPort), runTcpConnection)

data ServerSettings a b es = ServerSettings
  { tcpOpts :: ServerOpts,
    action :: a -> IO b
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
run (ServerSettings {tcpOpts, action})  = runEff (runConcurrent (runTcpConnSupplier tcpOpts (runServer @a @b @Socket action)))

-- runTcpConnSupplier' opts action = runEff (runConcurrent (runTcpConnSupplier opts action))

-- runClient opts action = runEff (runConcurrent (runTcpConnection opts action))

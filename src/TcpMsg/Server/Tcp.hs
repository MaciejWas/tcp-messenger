{-# LANGUAGE AllowAmbiguousTypes #-}
{-# LANGUAGE ConstraintKinds #-}
{-# LANGUAGE DataKinds #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE NamedFieldPuns #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE TypeOperators #-}

module TcpMsg.Server.Tcp where

import Control.Exception (finally)

import Control.Concurrent (ThreadId)
import Effectful
  ( Eff,
    IOE,
    MonadIO (liftIO),
    runEff,
    (:>),
  )
import Effectful.Concurrent (Concurrent, forkIO, runConcurrent)
import Effectful.Concurrent.STM (newTVarIO)
import Effectful.Dispatch.Static (unsafeEff_)
import qualified Network.Socket as Net
  ( PortNumber,
    Socket,
    accept,
    close,
    gracefulClose,
    openSocket,
  )
import qualified Network.Socket.ByteString as Net
import TcpMsg.Effects.Connection (ConnectionActions, ConnectionHandle (ConnectionHandle), ConnectionInfo (ConnectionInfo), mkConnectionActions)
import TcpMsg.Effects.Supplier (ConnSupplier, ConnSupplierActions (ConnSupplierActions), runConnSupplier)
import TcpMsg.Network (getAddr, startListening)

----------------------------------------------------------------------------------------------------------

data ServerOpts = ServerOpts
  { port :: Net.PortNumber
  }

spawnServer :: ServerOpts -> IO Net.Socket
spawnServer (ServerOpts {port}) = do
  socketAddress <- getAddr "localhost" port
  socket <- Net.openSocket socketAddress
  startListening socket socketAddress
  return socket


----------------------------------------------------------------------------------------------------------

nextConnection :: (Concurrent :> es) => Net.Socket -> Eff es (ConnectionActions Net.Socket)
nextConnection sock = do
  (peerSocket, peerAddr) <- unsafeEff_ (Net.accept sock)
  connRef <- newTVarIO (ConnectionHandle (ConnectionInfo "some conn") peerSocket)
  mkConnectionActions
    connRef
    (Net.recv peerSocket)
    (Net.sendAll peerSocket)
    (Net.gracefulClose peerSocket 500)

----------------------------------------------------------------------------------------------------------

defaultServerOpts :: ServerOpts
defaultServerOpts = ServerOpts {port = 4455}

data ServerHandle = ServerHandle
  { kill :: IO (),
    threadId :: ThreadId
  }

-- | Runs a `ConnSupplier` effect. In other words, provides an environment where
-- | a new connection can be awaited and handled
runTcpConnSupplier ::
  (IOE :> es, Concurrent :> es) =>
  ServerOpts ->
  Eff (ConnSupplier Net.Socket ': es) () ->
  Eff es ServerHandle
runTcpConnSupplier
  opts
  operation =
    do
      socket <- liftIO (spawnServer opts)
      tid <-
        forkIO
          ( runConnSupplier
              ( ConnSupplierActions
                  (runEff (runConcurrent (nextConnection socket)))
              )
              operation
          )
      return
        ( ServerHandle
            { kill = Net.gracefulClose socket 30,
              threadId = tid
            }
        )

----------------------------------------------------------------------------------------------------------

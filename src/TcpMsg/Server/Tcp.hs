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

import Control.Concurrent (ThreadId, forkFinally)
import qualified Control.Exception as E
import Control.Monad (void)
import Effectful
  ( Eff,
    IOE,
    MonadIO (liftIO),
    runEff,
    (:>),
  )
import Effectful.Concurrent (Concurrent, forkIO, runConcurrent)
import Effectful.Concurrent.STM (newTVarIO)
import Effectful.Dispatch.Static (unsafeEff, unsafeEff_)
import Network.Socket (SocketOption (ReuseAddr), setCloseOnExecIfNeeded)
import qualified Network.Socket as Net
  ( AddrInfo (..),
    AddrInfoFlag (AI_ADDRCONFIG),
    Family (AF_UNSPEC),
    HostName,
    PortNumber,
    ProtocolNumber,
    SockAddr (SockAddrInet),
    Socket,
    SocketType (NoSocketType),
    accept,
    bind,
    close,
    connect,
    getAddrInfo,
    gracefulClose,
    listen,
    openSocket,
    setSocketOption,
    withFdSocket,
  )
import qualified Network.Socket.ByteString as Net
import TcpMsg.Effects.Connection (Conn, ConnectionActions, ConnectionHandle (ConnectionHandle), ConnectionInfo (ConnectionInfo), mkConnectionActions, runConnection)
import TcpMsg.Effects.Supplier (ConnSupplier, ConnSupplierActions (ConnSupplierActions), runConnSupplier)

----------------------------------------------------------------------------------------------------------

-- | Effect definition
-- data Network :: Effect

-- type instance DispatchOf Network = Static WithSideEffects

-- newtype instance StaticRep Network = NetworkSocket Net.Socket

-- maximum number of queued connections

data ServerOpts = ServerOpts
  { port :: Net.PortNumber
  }

maxQueuedConn :: Int
maxQueuedConn = 1024

defaultProtocolNumber :: Net.ProtocolNumber
defaultProtocolNumber = 0

defaultAddrInfo :: Net.AddrInfo
defaultAddrInfo =
  Net.AddrInfo
    { Net.addrFlags = [Net.AI_ADDRCONFIG],
      Net.addrFamily = Net.AF_UNSPEC,
      Net.addrSocketType = Net.NoSocketType,
      Net.addrProtocol = defaultProtocolNumber,
      Net.addrAddress = Net.SockAddrInet 0 0,
      Net.addrCanonName = Nothing
    }

defaultSocketOptions :: [(SocketOption, Int)]
defaultSocketOptions = [(ReuseAddr, 1)]

setDefaultSocketOptions :: Net.Socket -> IO ()
setDefaultSocketOptions sock =
  mapM_
    setOption
    defaultSocketOptions
  where
    setOption = uncurry (Net.setSocketOption sock)

startListening :: Net.Socket -> Net.AddrInfo -> IO ()
startListening sock addr = do
  setDefaultSocketOptions sock
  Net.withFdSocket sock setCloseOnExecIfNeeded
  Net.bind sock (Net.addrAddress addr)
  Net.listen sock maxQueuedConn

getAddr :: Net.HostName -> Net.PortNumber -> IO Net.AddrInfo
getAddr hostName portNumber =
  let hints = Just defaultAddrInfo
      hostInfo = Just hostName
      portInfo = Just (show portNumber)
   in head <$> Net.getAddrInfo hints hostInfo portInfo

spawnServer :: ServerOpts -> IO Net.Socket
spawnServer (ServerOpts {port}) = do
  socketAddress <- getAddr "localhost" port
  socket <- Net.openSocket socketAddress
  startListening socket socketAddress
  return socket

spawnClient :: ClientOpts -> IO Net.Socket
spawnClient (ClientOpts {serverHost, serverPort}) = do
  addrInfo <- getAddr serverHost serverPort
  serverSocket <- Net.openSocket addrInfo
  Net.connect serverSocket (Net.addrAddress addrInfo)
  return serverSocket

onConnectionDo :: forall a. Net.Socket -> (Net.Socket -> Net.SockAddr -> IO a) -> IO ()
onConnectionDo sock action =
  E.bracketOnError
    (Net.accept sock)
    (Net.close . fst)
    ( \(conn, peer) ->
        void
          ( forkFinally
              (action conn peer)
              (const $ Net.gracefulClose conn 5000)
          )
    )

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

runTcpServer ::
  (IOE :> es, Concurrent :> es) =>
  ServerOpts ->
  Eff (ConnSupplier Net.Socket ': es) () ->
  Eff es ServerHandle
runTcpServer
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
            { kill = Net.close socket,
              threadId = tid
            }
        )

----------------------------------------------------------------------------------------------------------

data ClientOpts = ClientOpts
  { serverHost :: Net.HostName,
    serverPort :: Net.PortNumber
  }

runTcpClient ::
  forall a es.
  (IOE :> es, Concurrent :> es) =>
  ClientOpts ->
  Eff (Conn Net.Socket ': es) a ->
  Eff es a
runTcpClient opts operation =
  do
    serverSocket <- liftIO (spawnClient opts)
    connRef <-
      newTVarIO
        ( ConnectionHandle
            (ConnectionInfo "some conn")
            serverSocket
        )
    connActions <-
      mkConnectionActions @es
        connRef
        (Net.recv serverSocket)
        (Net.sendAll serverSocket)
        (Net.gracefulClose serverSocket 500)

    runConnection
      connActions
      operation

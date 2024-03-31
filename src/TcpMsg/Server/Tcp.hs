{-# LANGUAGE NamedFieldPuns #-}
{-# LANGUAGE OverloadedStrings #-}

module TcpMsg.Server.Tcp
  ( ServerTcpSettings (..),
    createTcpConnSupplier,
    defaultServerTcpSettings,
  )
where

import Control.Concurrent.STM.TVar (newTVarIO)
import qualified Network.Socket as Net
  ( PortNumber,
    Socket,
    accept,
    gracefulClose,
    openSocket,
  )
import qualified Network.Socket.ByteString as Net
import TcpMsg.Connection (Connection, ConnectionHandle (ConnectionHandle), ConnectionInfo (ConnectionInfo), mkConnection)
import TcpMsg.Network (getAddr, startListening)
import TcpMsg.Server.Abstract (ConnectionSupplier (ConnectionSupplier, finalize, nextConnection))

----------------------------------------------------------------------------------------------------------

data ServerTcpSettings = ServerTcpSettings
  { port :: Net.PortNumber
  }

----------------------------------------------------------------------------------------------------------

createServerSocket :: ServerTcpSettings -> IO Net.Socket
createServerSocket (ServerTcpSettings {port}) = do
  socketAddress <- getAddr "localhost" port
  socket <- Net.openSocket socketAddress
  startListening socket socketAddress
  return socket

----------------------------------------------------------------------------------------------------------

nextTcpConnection :: Net.Socket -> IO (Connection Net.Socket)
nextTcpConnection sock = do
  (peerSocket, peerAddr) <- Net.accept sock
  connRef <- newTVarIO (ConnectionHandle (ConnectionInfo "some conn") peerSocket)
  mkConnection
    connRef
    (Net.recv peerSocket)
    (Net.sendAll peerSocket)

----------------------------------------------------------------------------------------------------------

defaultServerTcpSettings :: ServerTcpSettings
defaultServerTcpSettings = ServerTcpSettings {port = 44551}

----------------------------------------------------------------------------------------------------------

createTcpConnSupplier ::
  ServerTcpSettings ->
  IO (ConnectionSupplier Net.Socket)
createTcpConnSupplier
  serverSettings =
    do
      socket <- createServerSocket serverSettings
      return
        ( ConnectionSupplier
            { nextConnection = nextTcpConnection socket,
              finalize = Net.gracefulClose socket 2000
            }
        )

{-# LANGUAGE AllowAmbiguousTypes #-}
{-# LANGUAGE ConstraintKinds #-}
{-# LANGUAGE DataKinds #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE TypeOperators #-}
{-# LANGUAGE OverloadedStrings #-}

module TcpMsg.Server.Tcp where

import Control.Concurrent (forkFinally)
import qualified Control.Exception as E
import Control.Monad (void)
import Effectful
  ( Eff,
    (:>), IOE, MonadIO (liftIO),
  )
import Network.Socket (SocketOption (ReuseAddr), setCloseOnExecIfNeeded)
import qualified Network.Socket as Net
  ( AddrInfo (..),
    AddrInfoFlag (AI_ADDRCONFIG),
    Family (AF_UNSPEC),
    ProtocolNumber,
    SockAddr (SockAddrInet),
    Socket,
    SocketType (NoSocketType),
    accept,
    bind,
    close,
    getAddrInfo,
    gracefulClose,
    listen,
    openSocket,
    setSocketOption,
    withFdSocket,
  )
import TcpMsg.Effects.Connection (ConnectionActions, mkConnectionActions, ConnectionHandle (ConnectionHandle), ConnectionInfo (ConnectionInfo))
import TcpMsg.Effects.Supplier (ConnSupplier(GetNextConn))
import Effectful.Dispatch.Dynamic (interpret)
import Effectful.Concurrent (Concurrent)
import Effectful.Concurrent.STM (newTVarIO)
import qualified Network.Socket.ByteString as Net

----------------------------------------------------------------------------------------------------------

-- | Effect definition
-- data Network :: Effect

-- type instance DispatchOf Network = Static WithSideEffects

-- newtype instance StaticRep Network = NetworkSocket Net.Socket

-- maximum number of queued connections
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

getAddr :: IO Net.AddrInfo
getAddr =
  let hints = Just defaultAddrInfo
      hostInfo = Just "0.0.0.0"
      portInfo = Just "4455"
   in head <$> Net.getAddrInfo hints hostInfo portInfo

type SocketRunner a = (Net.Socket -> Net.SockAddr -> IO a)

spawnServer :: IO Net.Socket
spawnServer  = do
  socketAddress <- getAddr
  socket <- Net.openSocket socketAddress
  startListening socket socketAddress
  return socket

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
  connRef <- newTVarIO (ConnectionHandle (ConnectionInfo "some conn" ) sock)
  mkConnectionActions 
    connRef
    (Net.recv sock)
    (Net.sendAll sock)

----------------------------------------------------------------------------------------------------------

runTcpServer ::
  (IOE :> es, Concurrent :> es) =>
  Eff (ConnSupplier Net.Socket ': es) a ->
  Eff es a
runTcpServer operation = do 
  socket <- liftIO spawnServer
  (interpret $ \_ -> \case
      GetNextConn -> nextConnection socket
    ) operation

-- {-# INLINE withSocket #-}
-- withSocket :: forall es b. (Network :> es) => (Net.Socket -> IO b) -> Eff es b
-- withSocket f = do
--   (NetworkSocket socket) <- (getStaticRep :: Eff es (StaticRep Network))
--   unsafeEff_ (f socket)

-- runNetwork :: forall es. Net.AddrInfo -> Eff (Network ': es) () -> Eff es ()
-- runNetwork addrInfo operation = do
--   socket <- unsafeEff_ (Net.openSocket addrInfo)
--   evalStaticRep (Conn connectionActions)

-- -- | Effectful operations

-- bind :: forall es. Network :> es => Net.SockAddr -> Eff es ()
-- bind sockAddr = withSocket (`Net.bind` sockAddr)

-- close :: forall es. Network :> es => Eff es ()
-- close = withSocket Net.close

-- listen :: forall es. Network :> es => Int -> Eff es ()
-- listen n = withSocket (`Net.listen` n)

-- receive :: forall es. Network :> es => Int -> Eff es BS.ByteString
-- receive nBytes = withSocket (`recv` nBytes)

-- send :: forall es. Network :> es => BS.ByteString -> Eff es ()
-- send bytes = withSocket (`sendAll` bytes)

{-# LANGUAGE AllowAmbiguousTypes #-}
{-# LANGUAGE ConstraintKinds #-}
{-# LANGUAGE DataKinds #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE TypeOperators #-}

module TcpMsg.Server.Tcp where

import Control.Exception (bracketOnError)
import qualified Data.ByteString as BS
import Effectful
  ( Dispatch (Static),
    DispatchOf,
    Eff,
    Effect,
    (:>),
  )
import Effectful.Dispatch.Static
  ( SideEffects (WithSideEffects),
    StaticRep,
    getStaticRep,
    unsafeEff_,
  )
import Network.Socket (SocketOption (ReuseAddr), defaultHints, getAddrInfo, setCloseOnExecIfNeeded)
import qualified Network.Socket as Net
  ( AddrInfo (..),
    AddrInfoFlag (AI_ADDRCONFIG),
    Family (AF_UNSPEC),
    ProtocolNumber,
    SockAddr (SockAddrInet),
    Socket,
    SocketType (NoSocketType),
    bind,
    close,
    getAddrInfo,
    listen,
    openSocket,
    setSocketOption,
    withFdSocket,
  )
import Network.Socket.ByteString (recv, sendAll)

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

setupSocket :: Net.Socket -> Net.AddrInfo -> IO ()
setupSocket sock addr = do
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

spawnServer :: IO ()
spawnServer = do
  socketAddress <- getAddr
  socket <- Net.openSocket socketAddress
  setupSocket socket socketAddress
  return ()

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

module TcpMsg.Network where

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
    bind,
    getAddrInfo,
    listen,
    setSocketOption,
    withFdSocket,
  )

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
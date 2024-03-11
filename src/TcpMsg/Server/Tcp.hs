module TcpMsg.Server.Tcp where
    

    import Control.Concurrent (forkFinally)
    import qualified Control.Exception as E
    import Control.Monad (unless, forever, void)
    import qualified Data.ByteString as S
    import Network.Socket
    import Network.Socket.ByteString (recv, sendAll)

{-# LANGUAGE ConstraintKinds #-}
{-# LANGUAGE DataKinds #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE QuantifiedConstraints #-}
{-# LANGUAGE RankNTypes #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE TypeOperators #-}

module TcpMsg.TcpServer where

import Control.Concurrent (ThreadId, forkIO)
import Control.Monad.IO.Class (liftIO)
import Data.Functor (void)
import Data.Serialize (Serialize)
import Effectful (Eff, IOE, runEff, (:>))
import Effectful.Concurrent (Concurrent, runConcurrent)
import Effectful.Concurrent.STM (TVar)
import TcpMsg.Connection
  ( Conn,
    ConnectionActions,
    ConnectionHandle,
    runConnection,
    writeBytes,
  )
import TcpMsg.Data (ServerOpts, mkMsg)
import TcpMsg.ParsingBuffers (parseMsg)

inParallel :: IO () -> IO ()
inParallel = void . forkIO

----------------------------------------------------------------------------------------------------------

data ServerHandle serverState connState = ServerHandle
  { stateOf :: TVar serverState,
    connectionsOf :: TVar [ConnectionHandle connState],
    threadOf :: ThreadId
  }

data ServerActions s c = ServerActions
  { startServerAction :: ServerOpts -> IO s,
    createHandlerAction :: s -> IO (ServerHandle s c),
    stopServerAction :: s -> IO (),
    -- Connection stuff.
    waitForConnAction :: s -> IO (ConnectionHandle c),
    prepareConnectionAction :: ConnectionHandle c -> IO (ConnectionActions c),
    stopConnAction :: ConnectionHandle c -> IO (),
    -- Stateful stuff.
    putStateAction :: s -> IO (),
    getStateAction :: IO s
  }

----------------------------------------------------------------------------------------------------------

runServer ::
  forall a b s c.
  (Serialize a, Serialize b) =>
  ServerOpts ->
  ServerActions s c ->
  (a -> IO b) ->
  IO (ServerHandle s c)
runServer opts actions respond = do
  serverState <- startServerAction actions opts
  handle <- createHandlerAction actions serverState
  (void . forkIO) (runConnections serverState)
  return handle
  where
    runConnections state = do
      connHandle <- waitForConnAction actions state
      connActions <- prepareConnectionAction actions connHandle

      ( void
          . forkIO
          . runEff
          . runConcurrent
          . runConnection connActions
        )
        handleConnection

      runConnections state

    handleConnection ::
      ( Conn c :> es,
        Concurrent :> es,
        IOE :> es
      ) =>
      Eff es ()
    handleConnection = do
      (header, msg :: a) <- parseMsg @c
      response <- liftIO (respond msg)
      let responseBytes = mkMsg 123 response
      writeBytes @c responseBytes
      handleConnection
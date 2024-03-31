{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE NamedFieldPuns #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE NumericUnderscores #-}

module ClientSpec (clientSpec) where

import Control.Concurrent (forkIO, killThread, newEmptyMVar, threadDelay)
import Control.Concurrent.Async (wait, mapConcurrently)
import Control.Monad (void, (>=>))
import Data.Serialize (Serialize)
import GHC.Generics (Generic)
import TcpMsg (ServerSettings (..), createClient, run)
import TcpMsg.Client.Tcp (ClientOpts (ClientOpts, serverHost, serverPort))
import TcpMsg.Client.Abstract (ask)
import TcpMsg.Data (Message (Message))

import TcpMsg.Server.Tcp (ServerTcpSettings (ServerTcpSettings, port))
import Test.Hspec
  ( describe,
    it,
    shouldBe, shouldSatisfy,
  )
import Data.UnixTime (getUnixTime, UnixTime (UnixTime))

--------------------------------------------------------------------------------------------------------------------------------------------------------

data SomeData = SomeData
  { foo :: String,
    bar :: [Int],
    baz :: Bool
  }
  deriving (Generic, Show, Eq)

instance Serialize SomeData

mkSomeData :: Int -> Message SomeData
mkSomeData i =
  Message
    SomeData {foo = show (i * 100), bar = [i .. (i + 30)], baz = False}
    Nothing

--------------------------------------------------------------------------------------------------------------------------------------------------------

clientSpec = do
  describe "Client" $ do
    it "can send a bytestring trunk" $ do
      let trunkData = "fasdfsdafasdf asdf asd fasd fdas fas fsdalllf fasdf asd"
      let request = Message (42 :: Int) (Just trunkData)

      tid <-
        forkIO
          ( void
              ( TcpMsg.run @Int @Bool
                  ( ServerSettings
                      { tcpOpts = ServerTcpSettings {port = 44551},
                        action = \(Message x t) -> return (Message (t == Just trunkData) t)
                      }
                  )
              )
          )

      threadDelay 1000

      let clientopts = ClientOpts {serverHost = "localhost", serverPort = 44551}
      client <- createClient clientopts
      response <- (client `ask` request) >>= wait
      response `shouldBe` Message True (Just trunkData)

      killThread tid
      threadDelay 100

    it "can send a single message to a server" $ do
      let request = Message (42 :: Int) Nothing

      -- Start a server which responds with x + 1
      tid <-
        forkIO
          ( void
              ( TcpMsg.run @Int @Int
                  ( ServerSettings
                      { tcpOpts = ServerTcpSettings {port = 44551},
                        action = \(Message x t) -> return (Message (x + 1) t)
                      }
                  )
              )
          )

      threadDelay 1000

      -- Start a client which sends a single request
      let clientOpts = ClientOpts {serverHost = "localhost", serverPort = 44551}
      client <- createClient clientOpts
      response <- (client `ask` request) >>= wait
      response `shouldBe` (Message (43 :: Int) Nothing)

      killThread tid

    it "can send a multiple messages to a server" $ do
      let requests = map mkSomeData [1 .. 200]
      let processRequest (Message x t) = Message x {baz = True} t

      -- Start a server which modifies the data
      tid <-
        forkIO
          ( void
              ( TcpMsg.run @SomeData @SomeData
                  ( ServerSettings
                      { tcpOpts = ServerTcpSettings {port = 44551},
                        action = return . processRequest
                      }
                  )
              )
          )

      threadDelay 1000

      -- Start a client which sends a single request
      let clientopts = ClientOpts {serverHost = "localhost", serverPort = 44551}
      client <- createClient clientopts
      responses <- mapM (ask client >=> wait) requests

      responses `shouldBe` map processRequest requests

      killThread tid

  describe "Server" $ do
    it "processes requests in parallel" $ do
      let requests = map (\i -> Message (123 :: Int) Nothing) [1..5]
      let oneSecond = 1_000_000

      -- Start a server which modifies the data
      tid <-
        forkIO
          ( void
              ( TcpMsg.run @Int @Int
                  ( ServerSettings
                      { tcpOpts = ServerTcpSettings {port = 44_551},
                        action = \m -> threadDelay oneSecond >> return (Message 123 Nothing)
                      }
                  )
              )
          )

      threadDelay 10_000

      -- Start a client which sends a single request
      let clientopts = ClientOpts {serverHost = "localhost", serverPort = 44_551}
      client <- createClient @Int @Int clientopts

      (UnixTime startSecs startMsecs) <- getUnixTime
      _responses <- mapConcurrently (ask client >=> wait) requests
      (UnixTime endSecs endMsecs) <- getUnixTime
      
      (endSecs - startSecs) `shouldSatisfy` (< 2)

      killThread tid

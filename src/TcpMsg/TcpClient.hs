{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE ScopedTypeVariables #-}

module TcpMsg.TcpClient where

import Control.Concurrent (ThreadId, forkIO)
import Control.Exception (bracket, finally)
import Control.Monad (forever)
import qualified Data.ByteString as BS
import Data.Functor (void)
import Data.Serialize (Serialize, encode)
import qualified Data.Text as T
import Debug.Trace (trace)
import GHC.IO.Device (IODevice (close))
import TcpMsg.Data (ServerOpts, mkMsg)
import TcpMsg.ParsingBuffers (parseMsg)

inParallel :: IO () -> IO ()
inParallel = void . forkIO

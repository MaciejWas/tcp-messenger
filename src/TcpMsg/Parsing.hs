module TcpMsg.Parsing where

import qualified Data.ByteString as BS
import Data.ByteString.Lazy (LazyByteString, toStrict)
import qualified Data.ByteString.Lazy as LBS
import Data.Serialize (Serialize, decode)
import TcpMsg.Data (Header (Header), Message (Message), headersize, FullMessage (FullMessage))
import TcpMsg.Connection (Connection, readBytes)

parseMsg ::
  (Serialize a) => Connection c -> IO (FullMessage a)
parseMsg conn = do
  header <- parseHeader conn
  payload <- parsePayload conn header
  trunk <- parseTrunk conn header
  return (FullMessage header (Message payload trunk) mempty)

parseHeader :: Connection c -> IO Header
parseHeader conn = parse conn headersize

parsePayload :: (Serialize m) => Connection c -> Header -> IO m
parsePayload c (Header _ msgSize _) = parse c msgSize

parseTrunk :: Connection c -> Header -> IO (Maybe LBS.LazyByteString)
parseTrunk conn (Header _ _ trunkSize) = case trunkSize of
  0 -> return Nothing
  _ -> do
    buf <- buffer conn mempty (fromIntegral trunkSize)
    return (if BS.null buf then Nothing else Just (LBS.fromStrict buf))

parse :: (Serialize a) => Connection c -> Int -> IO a
parse conn n = do
  buf <- buffer conn (mempty :: LazyByteString) n
  case decode buf of
    Right val -> return val
    Left e -> error e

buffer :: Connection c -> LazyByteString -> Int -> IO BS.ByteString
buffer conn currBuffer remainingBytes = do
  newBytes <- conn `readBytes` remainingBytes
  let bytesInLastMessage = BS.length newBytes
  if bytesInLastMessage == remainingBytes
    then return (toStrict currBuffer <> newBytes)
    else
      let updatedBuffer = currBuffer <> BS.fromStrict newBytes
          updatedRemaining = remainingBytes - bytesInLastMessage
       in buffer conn updatedBuffer updatedRemaining

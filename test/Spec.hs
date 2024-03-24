import Test.Hspec (hspec)

import ParserSpec (parserSpec)
import ServerSpec (serverSpec)
import ClientSpec (clientSpec)

main :: IO ()
main = hspec (do
  clientSpec
  serverSpec
  parserSpec
  )
  
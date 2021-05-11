# hspec-golden-cereal

## Arbitrary

GoldenSpecs functions write golden files if they do not exist. When they do
exist they use a seed from the golden file to create an arbitrary value of a
type and check if the serialization matches the file. If it fails it means
that there has been a change in the Aeson serialization or a change in the
data type.

RoundtripSpecs make sure that a type is able to be encoded to binary, decoded
from binary back to the original type, and equal the same value. If it fails
then there may be an issue with the Data.Serialize instance.

## ToADTArbitrary

`ToADTArbitrary` is a type class that helps create arbitrary values for every
constructor in a type. GoldenADTSpecs and RoundtripADTSpecs function similarly
to their `Arbitrary` counterparts, but will specifically test each constructor.
This is very useful for sum types.

## Usage

```haskell
{-# LANGUAGE DeriveGeneric #-}

-- base
import GHC.Generics (Generic)
import Data.Proxy

-- Cereal
import Data.Serialize

-- QuickCheck
import Test.QuickCheck (Arbitrary (..), oneof)

-- quickcheck-arbitrary-adt
import Test.QuickCheck.Arbitrary.ADT (ToADTArbitrary)

data Person = Person
  { name :: String,
    address :: String,
    age :: Int
  }
  deriving (Eq, Read, Show, Generic)

instance Serialize Person

instance ToADTArbitrary Person

instance Arbitrary Person where
  arbitrary = Person <$> arbitrary <*> arbitrary <*> arbitrary

-- sum type
data OnOrOff
  = On
  | Off
  deriving (Eq, Read, Show, Generic)

instance Serialize OnOrOff

instance ToADTArbitrary OnOrOff

instance Arbitrary OnOrOff where
  arbitrary = oneof [pure On, pure Off]



main :: IO ()
main = do
  -- only create the golden files, do not run tests
  mkGoldenFileForType 10 (Proxy :: Proxy Person) "golden"
  mkGoldenFileForType 10 (Proxy :: Proxy OnOrOff) "golden"
  
  -- for an arbitrary instance of each constructor
  -- make sure that ToJSON and FromJSON are defined such that 
  -- they same value is maintained
  roundtripSpecs (Proxy :: Proxy Person)
  roundtripSpecs (Proxy :: Proxy OnOrOff)

  -- the first time it create files if they do not exist
  -- if they exist then it will test serialization against the files along with the roundtrip tests
  -- files are saved in "golden" dir.
  goldenSpecs (Proxy :: Proxy Person)
  goldenSpecs (Proxy :: Proxy OnOrOff)
  
  -- use the module name as a dir when saving and opening files
  goldenSpecs (defaultSettings { useModuleNameAsSubDirectory = True }) (Proxy :: Proxy Person)
  goldenSpecs (defaultSettings { useModuleNameAsSubDirectory = True }) (Proxy :: Proxy OnOrOff)
  
  -- control the location of the golde files
  let topDir = "bin-tests"
  goldenSpecs (defaultSettings {goldenDirectoryOption = CustomDirectoryName topDir}) (Proxy :: Proxy Person)
  goldenSpecs (defaultSettings {goldenDirectoryOption = CustomDirectoryName topDir}) (Proxy :: Proxy OnOrOff)

```

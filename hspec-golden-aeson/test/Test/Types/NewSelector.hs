{-# LANGUAGE DeriveGeneric #-}

module Test.Types.NewSelector where

import Data.Serialize
import GHC.Generics
import Test.QuickCheck
import Test.QuickCheck.Arbitrary.ADT

data Person = Person
  { name :: String,
    age :: Int,
    address :: String
  }
  deriving (Eq, Show, Generic)

instance Serialize Person

instance ToADTArbitrary Person

instance Arbitrary Person where
  arbitrary = genericArbitrary

data SumType
  = SumType1 Int
  | SumType2 String Int
  | SumType3 Double String Int
  deriving (Eq, Show, Generic)

instance Serialize SumType

instance ToADTArbitrary SumType

instance Arbitrary SumType where
  arbitrary = genericArbitrary

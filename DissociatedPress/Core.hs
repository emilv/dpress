module DissociatedPress.Core (
    Dictionary (..),
    newDict, defDict, updateDict, setPreferredKeyLength,
    disPress, disPressBack, {-randomPress,
    randomKey,-} toKey, isKeyIn, optKey, merge
  ) where
import qualified DissociatedPress.NGram as N
import Data.List
import System.Random

data Ord a => Dictionary a = Dictionary {
    maxKeyLen    :: Int,
    preferKeyLen :: Int,
    twoWay       :: Bool,
    dict         :: N.NGram a,
    dict2        :: N.NGram a
  }

-- | Create a dictionary with default settings. This dictionary is optimized
--   for producing nice text with short keylengths. See 'newDict' for the
--   default settings used for this dictionary.
defDict :: Ord a => Dictionary a
defDict = Dictionary {
    maxKeyLen    = 3,
    preferKeyLen = 3,
    twoWay       = True,
    dict         = N.empty,
    dict2        = N.empty
  }

-- | Sets the preferred key length of the given dictionary. The value is
--   to the maximum key length.
setPreferredKeyLength :: Ord a => Int -> Dictionary a -> Dictionary a
setPreferredKeyLength len d =
  d {preferKeyLen = min len (maxKeyLen d)}

-- | Generate a new dictionary with custom settings.
newDict :: Ord a
        => Int          -- ^ Maximum key length that can be used with this
                        --   dictionary. Dictionary size increases linear
                        --   to this parameter.
                        --   Default: 3
        -> Int          -- ^ Preferred key length. If a key is used that is
                        --   shorter than this, the generator will try to
                        --   derive a key of this length to improve the
                        --   generated results. Setting this to 0 means that
                        --   the generator will never try to optimize keys.
                        --   Default: 3
        -> Bool         -- ^ Is this a two way dictionary or not? A two way
                        --   dictionary may be used to generate sentences
                        --   backwards from the provided key, whereas one way
                        --   dictionaries can only be used to generate forward.
                        --   A two way dictionary takes up roughly twice as
                        --   as much memory as the equivalent one way dict.
                        --   Default: True
        -> Dictionary a
newDict max prefer twoway = defDict {
    maxKeyLen    = max,
    preferKeyLen = prefer,
    twoWay       = twoway
  }

-- | Merges two dictionaries. The resulting dictionaries will use lowest
--   common denominator settings; lowest max and preferred key lengths, only
--   use forward dictionary unless both dictionaries are two way.
--   It is worth noting that the first dictionary will be merged into the
--   second one. Thus, if you have a small dictionary a and a large dictionary
--   b that you wish to merge, doing merge a b would be faster than doing
--   merge b a.
merge :: Ord a => Dictionary a -> Dictionary a -> Dictionary a
merge a b =
  Dictionary {
      maxKeyLen    = kLen,
      preferKeyLen = kPref,
      twoWay       = tWay,
      dict         = d1,
      dict2        = d2
    }
  where
    kLen  = min (maxKeyLen a) (maxKeyLen b)
    kPref = min (preferKeyLen a) (preferKeyLen b)
    tWay  = twoWay a && twoWay b
    d1    = N.merge (dict a) (dict b)
    d2    = if tWay
               then N.merge (dict2 a) (dict2 b)
               else N.empty

-- | Update a dictionary with the associations from the given list of words.
updateDict :: Ord a => [a] -> Dictionary a -> Dictionary a
updateDict words d = d2 where
    d1 = if twoWay d
            then updateDict' (reverse words) d{dict=dict2 d, dict2=dict d}
            else d {dict = dict2 d, dict2 = dict d}
    d2 = updateDict' words d {dict = dict2 d1, dict2 = dict d1}

-- | Update only the forward dictionary using the given word list.
updateDict' :: Ord a => [a] -> Dictionary a -> Dictionary a
updateDict' words@(w:ws@(_:_)) d =
  updateDict' ws d {dict = dict'}
  where
    dict' = N.insert (take (maxKeyLen d+1) words) (dict d)
updateDict' _ dict        =
  dict

-- | Try to use the given key and random generator to derive a preferred length
--   key for this dictionary.
optKey :: Ord a
       => (Dictionary a -> N.NGram a) -- ^ Use dict or dict2?
       -> Dictionary a                   -- ^ Dictionary to work on
       -> StdGen                         -- ^ Random generator
       -> [a]                            -- ^ Key to optimize
       -> [a]
optKey whatDict dic gen key
  | length key >= preferKeyLen dic = key
  | otherwise                      = optKey whatDict dic gen' key'
    where
      key'        = key ++ [fst $ pickOne possible gen]
      possible    = (whatDict dic) N.! key
      (idx, gen') = randomR (0, length possible-1) gen

-- | Generate text backward from the given key
disPressBack :: Ord a => [a] -> Dictionary a -> StdGen -> [a]
disPressBack key d gen = disPress' dict2 (reverse key) d gen

-- | Generate text forward from the given key
disPress :: Ord a => [a] -> Dictionary a -> StdGen -> [a]
disPress = disPress' dict

-- | Helper for disPress and disPressBack; generates text forward or backward
--   depending on if the first parameter is dict or dict2.
disPress' :: Ord a
          => (Dictionary a -> N.NGram a)
          -> [a]
          -> Dictionary a
          -> StdGen
          -> [a]
disPress' whatDict key@(w:ws) d gen =
  case word of
    Just (word', gen') ->
      w : disPress' whatDict (optKey whatDict d gen $ ws++[word']) d gen'
    _         ->
      disPress' whatDict ws d gen
  where
    word = do
      possible <- N.lookup key (whatDict d)
      return $ pickOne possible gen
disPress' _ _ _ _ = []

pickOne :: Ord a => [(a, Int)] -> StdGen -> (a, StdGen)
pickOne items g = (pick items num, g')
  where
    pick ((x, w):xs) n | n <= w    = x
                       | otherwise = pick xs (n-w)
    total     = sum $ map snd items
    (num, g') = randomR (1, total) g

-- | Randomly chooses a key for the map. The key uses only a single word,
--   so that it can be used properly for both forward and backward generation.
{-randomKey :: Ord a => Dictionary a -> StdGen -> [a]
randomKey dic gen = [key]
  where
    (idx, gen')   = randomR (0, 0 {-(N.size $ dict dic) - 1-}) gen
    (idx2, gen'') = randomR (0, length possible - 1) gen'
    possible      = (N.elems $ dict dic) !! idx
    key           = possible !! idx2-}

-- | Takes a (possibly) too long key and returns the longest subset of the key
--   that is actually a key in the given dictionary.
--   If the boolean parameter is True, subsequences later in the key are
--   preferred to those earlier. Default is to prefer earlier sequences.
toKey :: Ord a => [a] -> Dictionary a -> Bool -> [a]
toKey s d rev =
  concat $ take 1 $ catKeys $ seqs s
  where
    -- it might be the case that a reversed list of sequences gives better
    -- results. we don't know, so let the user specify whether he thinks so
    -- or not.
    seqs ws = sortBy longestFirst
              $ ((if rev then reverse else id) $ subsequences s)
    catKeys = foldr (\x a -> if x `isKeyIn` d then x:a else a) []
    longestFirst a b =
      case compare (length a) (length b) of
        GT -> LT
        LT -> GT
        _  -> EQ

-- | Returns true if the given key is valid for the given dictionary; that is,
--   if it points to something.
isKeyIn :: Ord a => [a] -> Dictionary a -> Bool
k `isKeyIn` d = N.lookup k (dict d) /= Nothing

-- | Generates text using a randomly selected key
-- randomPress :: Ord a => Dictionary a -> StdGen -> [a]
-- randomPress dic gen = disPress (randomKey dic gen) dic gen

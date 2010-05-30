-- | Trie-like data structure, specialized for storing n-grams.
module DissociatedPress.NGram (
    NGram (..),
    empty, insert, DissociatedPress.NGram.lookup, delete, (!), elems,
    fold, merge
  ) where
import qualified Data.Map as M
import Data.Maybe

data NGram a = NGram {
    weight   :: Int,
    children :: M.Map a (NGram a)
  } deriving Show

-- | An empty n-gram trie
empty :: NGram a
empty = NGram {weight = 0, children = M.empty}

-- | Returns the set of keys following the given key.
(!) :: Ord a => NGram a -> [a] -> [(a, Int)]
t ! k = fromJust $ DissociatedPress.NGram.lookup k t

-- | Standard fold over all n-grams in the trie.
fold :: Ord b => (a -> [(b, Int)] -> a) -> a -> NGram b -> a
fold f acc ngram = foldl f acc (elems ngram)

-- | Merge two n-gram tries together.
merge :: Ord a => NGram a -> NGram a -> NGram a
merge a b = fold ins b a
  where
    ins t k = insert (map fst k) t

-- | Return a list of all n-grams in the trie.
elems :: Ord a => NGram a -> [[(a, Int)]]
elems (NGram w t) = M.foldWithKey extract [] t
  where
    extract k v acc =
      case elems v of
        [] -> [(k, w)]:acc
        ev ->  (map ((k, w):) ev) ++ acc

-- | Insert a new n-gram into the trie.
insert :: Ord a => [a] -> NGram a -> NGram a
insert (k:ks) t =
  t {weight = weight t + 1, children = M.alter f k (children t)}
    where
      f (Just t') = Just $ insert ks t'
      f _         = Just $ insert ks empty
insert _ t =
  t {weight = weight t + 1}

-- | Return all keys following the given key in the trie.
lookup :: Ord a => [a] -> NGram a -> Maybe [(a, Int)]
lookup (k:ks) t = do
  child <- M.lookup k (children t)
  DissociatedPress.NGram.lookup ks child
lookup [] (NGram _ t) =
  if null $ M.keys t
     then Nothing
     else Just $ map (\(k, NGram w _) -> (k, w)) $ M.toList t

-- | Delete a key from the trie. Note that deleting a key will also remove all
--   children of that key. For example, delete "abc" $ insert "abcde" will
--   leave you with an empty trie.
delete :: Ord a => [a] -> NGram a -> NGram a
delete (k:ks@(_:_)) t =
  t {children = M.alter f k (children t)}
    where
      f (Just t') = Just $ delete ks t'
      f _         = Nothing
delete [_] t =
  DissociatedPress.NGram.empty
delete [] t  =
  DissociatedPress.NGram.empty

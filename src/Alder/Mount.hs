{-# LANGUAGE EmptyDataDecls    #-}
{-# LANGUAGE OverloadedStrings #-}
module Alder.Mount
    ( mount
    ) where

import           Control.Monad
import           Control.Monad.State.Class
import           Control.Monad.Trans
import           Data.Aeson
import           Data.HashMap.Strict       as HashMap
import           Data.IORef
import           Data.Maybe
import           Data.Monoid
import           Data.Text                 as Text
import           GHCJS.Types

import           Alder.Html.Internal
import           Alder.IOState
import           Alder.JavaScript

data NativeElement

type DOMElement = JSRef NativeElement

data Element
    = Element !Text Attributes [Element]
    | Text !Text

-- TODO: consolidate text nodes
fromHtml :: HtmlM a -> [Element]
fromHtml html = go mempty html []
  where
    go attrs m = case m of
        Empty            -> id
        Append a b       -> go attrs a . go attrs b
        Parent t h       -> (Element t (applyAttributes attrs) (fromHtml h) :)
        Leaf t           -> (Element t (applyAttributes attrs) [] :)
        Content t        -> (Text t :)
        AddAttribute a h -> go (a <> attrs) h

    applyAttributes (Attribute f) = f mempty

type Name = Int

data MountState = MountState
    { nextName :: !Name
    , eventMap :: !(HashMap Name Handlers)
    }

type Mount = IOState MountState

ignore :: m () -> m ()
ignore = id

mount :: IO (Html -> IO ())
mount = do
    ref <- newIORef MountState
        { nextName = 0
        , eventMap = HashMap.empty
        }
    return $ \html -> runIOState (update html) ref

nameAttr :: Text
nameAttr = "data-alder-id"

register :: DOMElement -> Handlers -> Mount ()
register e h = do
    name <- gets nextName
    ignore $ apply e "setAttribute" (nameAttr, Text.pack $ show name)
    modify $ \s -> s
        { nextName = name + 1
        , eventMap = HashMap.insert name h (eventMap s)
        }

dispatch :: DOMElement -> Text -> Value -> Mount ()
dispatch e eventName obj = do
    field <- call e "getAttribute" nameAttr
    m <- gets eventMap
    fromMaybe (return ()) $ do
        name <- readMaybe (Text.unpack field)
        hs   <- HashMap.lookup name m
        h    <- HashMap.lookup eventName hs
        return $ liftIO (h obj)
  where
    readMaybe s = case reads s of
        [(a,"")] -> Just a
        _        -> Nothing

update :: Html -> Mount ()
update html = do
    let new = fromHtml html
    doc <- global "document"
    body <- getProp doc "body"
    modify $ \s -> s { eventMap = HashMap.empty }
    removeChildren body
    createChildren body new

create :: Element -> Mount DOMElement
create (Element t attrs cs) = do
    doc <- global "document"
    e <- call doc "createElement" t
    register e (handlers attrs)
    forM_ (HashMap.toList $ attributes attrs) $ \(k, v) ->
        ignore $ apply e "setAttribute" (k, v)
    createChildren e cs
    return e
create (Text t) = do
    doc <- global "document"
    call doc "createTextNode" t

createChildren :: DOMElement -> [Element] -> Mount ()
createChildren parent cs = do
    children <- mapM create cs
    forM_ children $ \child ->
        ignore $ call parent "appendChild" child

removeChildren :: DOMElement -> Mount ()
removeChildren parent = go
  where
    go = do
        r <- getProp parent "lastChild"
        case r of
            Nothing -> return ()
            Just c  -> do
                ignore $ call parent "removeChild" (c :: DOMElement)
                go

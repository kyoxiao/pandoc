{-
Copyright (C) 2006-7 John MacFarlane <jgm@berkeley.edu>

This program is free software; you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation; either version 2 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program; if not, write to the Free Software
Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA
-}

{- |
   Module      : Text.Pandoc.Shared
   Copyright   : Copyright (C) 2006-7 John MacFarlane
   License     : GNU GPL, version 2 or above 

   Maintainer  : John MacFarlane <jgm@berkeley.edu>
   Stability   : alpha
   Portability : portable

Utility functions and definitions used by the various Pandoc modules.
-}
module Text.Pandoc.Shared ( 
                     -- * List processing
                     splitBy,
                     splitByIndices,
                     substitute,
                     joinWithSep,
                     -- * Text processing
                     tabsToSpaces,
                     backslashEscapes,
                     escapeStringUsing,
                     stripTrailingNewlines,
                     removeLeadingTrailingSpace,
                     removeLeadingSpace,
                     removeTrailingSpace,
                     stripFirstAndLast,
                     camelCaseToHyphenated,
                     toRomanNumeral,
                     -- * Parsing
                     (>>~),
                     anyLine,
                     many1Till,
                     notFollowedBy',
                     oneOfStrings,
                     spaceChar,
                     skipSpaces,
                     blankline,
                     blanklines,
                     enclosed,
                     stringAnyCase,
                     parseFromString,
                     lineClump,
                     charsInBalanced,
                     charsInBalanced',
                     romanNumeral,
                     withHorizDisplacement,
                     nullBlock,
                     failIfStrict,
                     escaped,
                     anyOrderedListMarker,
                     orderedListMarker,
                     charRef,
                     readWith,
                     testStringWith,
                     ParserState (..),
                     defaultParserState,
                     Reference (..),
                     isNoteBlock,
                     isKeyBlock,
                     isLineClump,
                     HeaderType (..),
                     ParserContext (..),
                     QuoteContext (..),
                     NoteTable,
                     KeyTable,
                     lookupKeySrc,
                     refsMatch,
                     -- * Native format prettyprinting
                     prettyPandoc,
                     -- * Pandoc block and inline list processing
                     orderedListMarkers,
                     normalizeSpaces,
                     compactify,
                     Element (..),
                     hierarchicalize,
                     isHeaderBlock,
                     -- * Writer options
                     WriterOptions (..),
                     defaultWriterOptions
                    ) where

import Text.Pandoc.Definition
import Text.ParserCombinators.Parsec
import Text.Pandoc.CharacterReferences ( characterReference )
import Data.Char ( toLower, toUpper, ord, chr, isLower, isUpper )
import Data.List ( find, groupBy, isPrefixOf, isSuffixOf )
import Control.Monad ( join )

--
-- List processing
--

-- | Split list by groups of one or more sep.
splitBy :: (Eq a) => a -> [a] -> [[a]]
splitBy _ [] = []
splitBy sep lst = 
  let (first, rest) = break (== sep) lst
      rest'         = dropWhile (== sep) rest
  in  first:(splitBy sep rest')

-- | Split list into chunks divided at specified indices.
splitByIndices :: [Int] -> [a] -> [[a]]
splitByIndices [] lst = [lst]
splitByIndices (x:xs) lst =
    let (first, rest) = splitAt x lst in
    first:(splitByIndices (map (\y -> y - x)  xs) rest)

-- | Replace each occurrence of one sublist in a list with another.
substitute :: (Eq a) => [a] -> [a] -> [a] -> [a]
substitute _ _ [] = []
substitute [] _ lst = lst
substitute target replacement lst = 
    if target `isPrefixOf` lst
       then replacement ++ (substitute target replacement $ drop (length target) lst)
       else (head lst):(substitute target replacement $ tail lst)

-- | Joins a list of lists, separated by another list.
joinWithSep :: [a]    -- ^ List to use as separator
            -> [[a]]  -- ^ Lists to join
            -> [a]
joinWithSep sep [] = []
joinWithSep sep lst = foldr1 (\a b -> a ++ sep ++ b) lst

--
-- Text processing
--

-- | Convert tabs to spaces (with adjustable tab stop).
tabsToSpaces :: Int     -- ^ Tabstop
             -> String  -- ^ String to convert
             -> String
tabsToSpaces tabstop str =
  unlines $ map (tabsInLine tabstop tabstop) (lines str)

-- | Convert tabs to spaces in one line.
tabsInLine :: Int      -- ^ Number of spaces to next tab stop
           -> Int      -- ^ Tabstop
           -> String   -- ^ Line to convert
           -> String
tabsInLine num tabstop [] = ""
tabsInLine num tabstop (c:cs) = 
  let (replacement, nextnum) = if c == '\t'
                                  then (replicate num ' ', tabstop)
                                  else if num > 1
                                          then ([c], num - 1)
                                          else ([c], tabstop)
  in  replacement ++ tabsInLine nextnum tabstop cs

-- | Returns an association list of backslash escapes for the
-- designated characters.
backslashEscapes :: [Char]    -- ^ list of special characters to escape
                 -> [(Char, String)]
backslashEscapes = map (\ch -> (ch, ['\\',ch]))

-- | Escape a string of characters, using an association list of
-- characters and strings.
escapeStringUsing :: [(Char, String)] -> String -> String
escapeStringUsing escapeTable [] = ""
escapeStringUsing escapeTable (x:xs) = 
  case (lookup x escapeTable) of
       Just str  -> str ++ rest
       Nothing   -> x:rest
  where rest = escapeStringUsing escapeTable xs

-- | Strip trailing newlines from string.
stripTrailingNewlines :: String -> String
stripTrailingNewlines = reverse . dropWhile (== '\n') . reverse

-- | Remove leading and trailing space (including newlines) from string.
removeLeadingTrailingSpace :: String -> String
removeLeadingTrailingSpace = removeLeadingSpace . removeTrailingSpace

-- | Remove leading space (including newlines) from string.
removeLeadingSpace :: String -> String
removeLeadingSpace = dropWhile (`elem` " \n\t")

-- | Remove trailing space (including newlines) from string.
removeTrailingSpace :: String -> String
removeTrailingSpace = reverse . removeLeadingSpace . reverse

-- | Strip leading and trailing characters from string
stripFirstAndLast :: String -> String
stripFirstAndLast str =
  drop 1 $ take ((length str) - 1) str

-- | Change CamelCase word to hyphenated lowercase (e.g., camel-case). 
camelCaseToHyphenated :: String -> String
camelCaseToHyphenated [] = ""
camelCaseToHyphenated (a:b:rest) | isLower a && isUpper b =
  a:'-':(toLower b):(camelCaseToHyphenated rest)
camelCaseToHyphenated (a:rest) = (toLower a):(camelCaseToHyphenated rest)

-- | Convert number < 4000 to uppercase roman numeral.
toRomanNumeral :: Int -> String
toRomanNumeral x =
  if x >= 4000 || x < 0
     then "?"
     else case x of
              x | x >= 1000 -> "M" ++ toRomanNumeral (x - 1000)
              x | x >= 900  -> "CM" ++ toRomanNumeral (x - 900)
              x | x >= 500  -> "D" ++ toRomanNumeral (x - 500)
              x | x >= 400  -> "CD" ++ toRomanNumeral (x - 400)
              x | x >= 100  -> "C" ++ toRomanNumeral (x - 100)
              x | x >= 90   -> "XC" ++ toRomanNumeral (x - 90)
              x | x >= 50   -> "L"  ++ toRomanNumeral (x - 50)
              x | x >= 40   -> "XL" ++ toRomanNumeral (x - 40)
              x | x >= 10   -> "X" ++ toRomanNumeral (x - 10)
              x | x >= 9    -> "IX" ++ toRomanNumeral (x - 5)
              x | x >= 5    -> "V" ++ toRomanNumeral (x - 5)
              x | x >= 4    -> "IV" ++ toRomanNumeral (x - 4)
              x | x >= 1    -> "I" ++ toRomanNumeral (x - 1)
              0             -> ""

--
-- Parsing
--

-- | Like >>, but returns the operation on the left.
-- (Suggested by Tillmann Rendel on Haskell-cafe list.)
(>>~) :: (Monad m) => m a -> m b -> m a
a >>~ b = a >>= \x -> b >> return x

-- | Parse any line of text
anyLine :: GenParser Char st [Char]
anyLine = manyTill anyChar (newline <|> (eof >> return '\n'))

-- | Like @manyTill@, but reads at least one item.
many1Till :: GenParser tok st a
	     -> GenParser tok st end
	     -> GenParser tok st [a]
many1Till p end = do
         first <- p
         rest <- manyTill p end
         return (first:rest)

-- | A more general form of @notFollowedBy@.  This one allows any 
-- type of parser to be specified, and succeeds only if that parser fails.
-- It does not consume any input.
notFollowedBy' :: Show b => GenParser a st b -> GenParser a st ()
notFollowedBy' p  = try $ join $  do  a <- try p
                                      return (unexpected (show a))
                                  <|>
                                  return (return ())
-- (This version due to Andrew Pimlott on the Haskell mailing list.)

-- | Parses one of a list of strings (tried in order).  
oneOfStrings :: [String] -> GenParser Char st String
oneOfStrings listOfStrings = choice $ map (try . string) listOfStrings

-- | Parses a space or tab.
spaceChar :: CharParser st Char
spaceChar = char ' ' <|> char '\t'

-- | Skips zero or more spaces or tabs.
skipSpaces :: GenParser Char st ()
skipSpaces = skipMany spaceChar

-- | Skips zero or more spaces or tabs, then reads a newline.
blankline :: GenParser Char st Char
blankline = try $ skipSpaces >> newline

-- | Parses one or more blank lines and returns a string of newlines.
blanklines :: GenParser Char st [Char]
blanklines = many1 blankline

-- | Parses material enclosed between start and end parsers.
enclosed :: GenParser Char st t   -- ^ start parser
	    -> GenParser Char st end  -- ^ end parser
	    -> GenParser Char st a    -- ^ content parser (to be used repeatedly)
	    -> GenParser Char st [a]
enclosed start end parser = try $ 
  start >> notFollowedBy space >> many1Till parser end

-- | Parse string, case insensitive.
stringAnyCase :: [Char] -> CharParser st String
stringAnyCase [] = string ""
stringAnyCase (x:xs) = do
  firstChar <- char (toUpper x) <|> char (toLower x)
  rest <- stringAnyCase xs
  return (firstChar:rest)

-- | Parse contents of 'str' using 'parser' and return result.
parseFromString :: GenParser tok st a -> [tok] -> GenParser tok st a
parseFromString parser str = do
  oldInput <- getInput
  setInput str
  result <- parser
  setInput oldInput
  return result

-- | Parse raw line block up to and including blank lines.
lineClump :: GenParser Char st String
lineClump = do
  lines <- many1 (notFollowedBy blankline >> anyLine)
  blanks <- blanklines <|> (eof >> return "\n")
  return $ (unlines lines) ++ blanks

-- | Parse a string of characters between an open character
-- and a close character, including text between balanced
-- pairs of open and close. For example,
-- @charsInBalanced '(' ')'@ will parse "(hello (there))"
-- and return "hello (there)".  Stop if a blank line is
-- encountered.
charsInBalanced :: Char -> Char -> GenParser Char st String
charsInBalanced open close = try $ do
  char open
  raw <- manyTill (   (do res <- charsInBalanced open close
                          return $ [open] ++ res ++ [close])
                  <|> (do notFollowedBy (blankline >> blanklines >> return '\n')
                          count 1 anyChar))
                  (char close)
  return $ concat raw

-- | Like @charsInBalanced@, but allow blank lines in the content.
charsInBalanced' :: Char -> Char -> GenParser Char st String
charsInBalanced' open close = try $ do
  char open
  raw <- manyTill (   (do res <- charsInBalanced open close
                          return $ [open] ++ res ++ [close])
                  <|> count 1 anyChar)
                  (char close)
  return $ concat raw

-- | Parses a roman numeral (uppercase or lowercase), returns number.
romanNumeral :: Bool                  -- ^ Uppercase if true
             -> GenParser Char st Int
romanNumeral upper = try $ do
    let charAnyCase c = char (if upper then toUpper c else c)
    let one = charAnyCase 'i'
    let five = charAnyCase 'v'
    let ten = charAnyCase 'x'
    let fifty = charAnyCase 'l'
    let hundred = charAnyCase 'c'
    let fivehundred = charAnyCase 'd'
    let thousand = charAnyCase 'm'
    thousands <- many thousand >>= (return . (1000 *) . length)
    ninehundreds <- option 0 $ try $ hundred >> thousand >> return 900
    fivehundreds <- many fivehundred >>= (return . (500 *) . length)
    fourhundreds <- option 0 $ try $ hundred >> fivehundred >> return 400
    hundreds <- many hundred >>= (return . (100 *) . length)
    nineties <- option 0 $ try $ ten >> hundred >> return 90
    fifties <- many fifty >>= (return . (50 *) . length)
    forties <- option 0 $ try $ ten >> fifty >> return 40
    tens <- many ten >>= (return . (10 *) . length)
    nines <- option 0 $ try $ one >> ten >> return 9
    fives <- many five >>= (return . (5 *) . length)
    fours <- option 0 $ try $ one >> five >> return 4
    ones <- many one >>= (return . length)
    let total = thousands + ninehundreds + fivehundreds + fourhundreds +
                hundreds + nineties + fifties + forties + tens + nines +
                fives + fours + ones
    if total == 0
       then fail "not a roman numeral"
       else return total

-- | Applies a parser, returns tuple of its results and its horizontal
-- displacement (the difference between the source column at the end
-- and the source column at the beginning). Vertical displacement
-- (source row) is ignored.
withHorizDisplacement :: GenParser Char st a  -- ^ Parser to apply
                      -> GenParser Char st (a, Int) -- ^ (result, displacement)
withHorizDisplacement parser = do
  pos1 <- getPosition
  result <- parser
  pos2 <- getPosition
  return (result, sourceColumn pos2 - sourceColumn pos1)

-- | Parses a character and returns 'Null' (so that the parser can move on
-- if it gets stuck).
nullBlock :: GenParser Char st Block
nullBlock = anyChar >> return Null

-- | Fail if reader is in strict markdown syntax mode.
failIfStrict :: GenParser Char ParserState ()
failIfStrict = do
    state <- getState
    if stateStrict state then fail "strict mode" else return ()

-- | Parses backslash, then applies character parser.
escaped :: GenParser Char st Char  -- ^ Parser for character to escape
        -> GenParser Char st Inline
escaped parser = try $ do
  char '\\'
  result <- parser
  return (Str [result])

-- | Parses an uppercase roman numeral and returns (UpperRoman, number).
upperRoman :: GenParser Char st (ListNumberStyle, Int)
upperRoman = do
  num <- romanNumeral True
  return (UpperRoman, num)

-- | Parses a lowercase roman numeral and returns (LowerRoman, number).
lowerRoman :: GenParser Char st (ListNumberStyle, Int)
lowerRoman = do
  num <- romanNumeral False
  return (LowerRoman, num)

-- | Parses a decimal numeral and returns (Decimal, number).
decimal :: GenParser Char st (ListNumberStyle, Int)
decimal = do
  num <- many1 digit
  return (Decimal, read num)

-- | Parses a '#' returns (DefaultStyle, 1).
defaultNum :: GenParser Char st (ListNumberStyle, Int)
defaultNum = do
  char '#'
  return (DefaultStyle, 1)

-- | Parses a lowercase letter and returns (LowerAlpha, number).
lowerAlpha :: GenParser Char st (ListNumberStyle, Int)
lowerAlpha = do
  ch <- oneOf ['a'..'z']
  return (LowerAlpha, ord ch - ord 'a' + 1)

-- | Parses an uppercase letter and returns (UpperAlpha, number).
upperAlpha :: GenParser Char st (ListNumberStyle, Int)
upperAlpha = do
  ch <- oneOf ['A'..'Z']
  return (UpperAlpha, ord ch - ord 'A' + 1)

-- | Parses a roman numeral i or I
romanOne :: GenParser Char st (ListNumberStyle, Int)
romanOne = (char 'i' >> return (LowerRoman, 1)) <|>
           (char 'I' >> return (UpperRoman, 1))

-- | Parses an ordered list marker and returns list attributes.
anyOrderedListMarker :: GenParser Char st ListAttributes 
anyOrderedListMarker = choice $ 
  [delimParser numParser | delimParser <- [inPeriod, inOneParen, inTwoParens],
                           numParser <- [decimal, defaultNum, romanOne,
                           lowerAlpha, lowerRoman, upperAlpha, upperRoman]]

-- | Parses a list number (num) followed by a period, returns list attributes.
inPeriod :: GenParser Char st (ListNumberStyle, Int)
         -> GenParser Char st ListAttributes 
inPeriod num = try $ do
  (style, start) <- num
  char '.'
  let delim = if style == DefaultStyle
                 then DefaultDelim
                 else Period
  return (start, style, delim)
 
-- | Parses a list number (num) followed by a paren, returns list attributes.
inOneParen :: GenParser Char st (ListNumberStyle, Int)
           -> GenParser Char st ListAttributes 
inOneParen num = try $ do
  (style, start) <- num
  char ')'
  return (start, style, OneParen)

-- | Parses a list number (num) enclosed in parens, returns list attributes.
inTwoParens :: GenParser Char st (ListNumberStyle, Int)
            -> GenParser Char st ListAttributes 
inTwoParens num = try $ do
  char '('
  (style, start) <- num
  char ')'
  return (start, style, TwoParens)

-- | Parses an ordered list marker with a given style and delimiter,
-- returns number.
orderedListMarker :: ListNumberStyle 
                  -> ListNumberDelim 
                  -> GenParser Char st Int
orderedListMarker style delim = do
  let num = case style of
               DefaultStyle -> decimal <|> defaultNum
               Decimal      -> decimal
               UpperRoman   -> upperRoman
               LowerRoman   -> lowerRoman
               UpperAlpha   -> upperAlpha
               LowerAlpha   -> lowerAlpha
  let context = case delim of
               DefaultDelim -> inPeriod
               Period       -> inPeriod
               OneParen     -> inOneParen
               TwoParens    -> inTwoParens
  (start, style, delim) <- context num
  return start

-- | Parses a character reference and returns a Str element.
charRef :: GenParser Char st Inline
charRef = do
  c <- characterReference
  return $ Str [c]

-- | Parse a string with a given parser and state.
readWith :: GenParser Char ParserState a      -- ^ parser
         -> ParserState                    -- ^ initial state
         -> String                         -- ^ input string
         -> a
readWith parser state input = 
    case runParser parser state "source" input of
      Left err     -> error $ "\nError:\n" ++ show err
      Right result -> result

-- | Parse a string with @parser@ (for testing).
testStringWith :: (Show a) => GenParser Char ParserState a
               -> String
               -> IO ()
testStringWith parser str = putStrLn $ show $ 
                            readWith parser defaultParserState str

-- | Parsing options.
data ParserState = ParserState
    { stateParseRaw        :: Bool,          -- ^ Parse raw HTML and LaTeX?
      stateParserContext   :: ParserContext, -- ^ Inside list?
      stateQuoteContext    :: QuoteContext,  -- ^ Inside quoted environment?
      stateKeys            :: KeyTable,      -- ^ List of reference keys
      stateNotes           :: NoteTable,     -- ^ List of notes
      stateTabStop         :: Int,           -- ^ Tab stop
      stateStandalone      :: Bool,          -- ^ Parse bibliographic info?
      stateTitle           :: [Inline],      -- ^ Title of document
      stateAuthors         :: [String],      -- ^ Authors of document
      stateDate            :: String,        -- ^ Date of document
      stateStrict          :: Bool,          -- ^ Use strict markdown syntax?
      stateSmart           :: Bool,          -- ^ Use smart typography?
      stateColumns         :: Int,           -- ^ Number of columns in terminal
      stateHeaderTable     :: [HeaderType]   -- ^ Ordered list of header types used
    }
    deriving Show

defaultParserState :: ParserState
defaultParserState = 
    ParserState { stateParseRaw        = False,
                  stateParserContext   = NullState,
                  stateQuoteContext    = NoQuote,
                  stateKeys            = [],
                  stateNotes           = [],
                  stateTabStop         = 4,
                  stateStandalone      = False,
                  stateTitle           = [],
                  stateAuthors         = [],
                  stateDate            = [],
                  stateStrict          = False,
                  stateSmart           = False,
                  stateColumns         = 80,
                  stateHeaderTable     = [] }

-- | References from preliminary parsing.
data Reference
  = KeyBlock [Inline] Target  -- ^ Key for reference-style link (label URL title)
  | NoteBlock String [Block]  -- ^ Footnote reference and contents
  | LineClump String          -- ^ Raw clump of lines with blanks at end
  deriving (Eq, Read, Show)

-- | Auxiliary functions used in preliminary parsing.
isNoteBlock :: Reference -> Bool
isNoteBlock (NoteBlock _ _) = True
isNoteBlock _ = False

isKeyBlock :: Reference -> Bool
isKeyBlock (KeyBlock _ _) = True
isKeyBlock _ = False

isLineClump :: Reference -> Bool
isLineClump (LineClump _) = True
isLineClump _ = False

data HeaderType 
    = SingleHeader Char  -- ^ Single line of characters underneath
    | DoubleHeader Char  -- ^ Lines of characters above and below
    deriving (Eq, Show)

data ParserContext 
    = ListItemState   -- ^ Used when running parser on list item contents
    | NullState       -- ^ Default state
    deriving (Eq, Show)

data QuoteContext
    = InSingleQuote   -- ^ Used when parsing inside single quotes
    | InDoubleQuote   -- ^ Used when parsing inside double quotes
    | NoQuote         -- ^ Used when not parsing inside quotes
    deriving (Eq, Show)

type NoteTable = [(String, [Block])]

type KeyTable = [([Inline], Target)]

-- | Look up key in key table and return target object.
lookupKeySrc :: KeyTable  -- ^ Key table
             -> [Inline]  -- ^ Key
             -> Maybe Target
lookupKeySrc table key = case find (refsMatch key . fst) table of
                           Nothing       -> Nothing
                           Just (_, src) -> Just src

-- | Returns @True@ if keys match (case insensitive).
refsMatch :: [Inline] -> [Inline] -> Bool
refsMatch ((Str x):restx) ((Str y):resty) = 
    ((map toLower x) == (map toLower y)) && refsMatch restx resty
refsMatch ((Emph x):restx) ((Emph y):resty) = 
    refsMatch x y && refsMatch restx resty
refsMatch ((Strong x):restx) ((Strong y):resty) = 
    refsMatch x y && refsMatch restx resty
refsMatch ((Strikeout x):restx) ((Strikeout y):resty) = 
    refsMatch x y && refsMatch restx resty
refsMatch ((Superscript x):restx) ((Superscript y):resty) = 
    refsMatch x y && refsMatch restx resty
refsMatch ((Subscript x):restx) ((Subscript y):resty) = 
    refsMatch x y && refsMatch restx resty
refsMatch ((Quoted t x):restx) ((Quoted u y):resty) = 
    t == u && refsMatch x y && refsMatch restx resty
refsMatch ((Code x):restx) ((Code y):resty) = 
    ((map toLower x) == (map toLower y)) && refsMatch restx resty
refsMatch ((TeX x):restx) ((TeX y):resty) = 
    ((map toLower x) == (map toLower y)) && refsMatch restx resty
refsMatch ((HtmlInline x):restx) ((HtmlInline y):resty) = 
    ((map toLower x) == (map toLower y)) && refsMatch restx resty
refsMatch (x:restx) (y:resty) = (x == y) && refsMatch restx resty
refsMatch [] x = null x
refsMatch x [] = null x

--
-- Native format prettyprinting
--
 
-- | Indent string as a block.
indentBy :: Int    -- ^ Number of spaces to indent the block 
         -> Int    -- ^ Number of spaces (rel to block) to indent first line
         -> String -- ^ Contents of block to indent
         -> String
indentBy num first [] = ""
indentBy num first str = 
  let (firstLine:restLines) = lines str 
      firstLineIndent = num + first
  in  (replicate firstLineIndent ' ') ++ firstLine ++ "\n" ++ 
      (joinWithSep "\n" $ map ((replicate num ' ') ++ ) restLines)

-- | Prettyprint list of Pandoc blocks elements.
prettyBlockList :: Int       -- ^ Number of spaces to indent list of blocks
                -> [Block]   -- ^ List of blocks
                -> String
prettyBlockList indent [] = indentBy indent 0 "[]"
prettyBlockList indent blocks = indentBy indent (-2) $ "[ " ++ 
  (joinWithSep "\n, " (map prettyBlock blocks)) ++ " ]"

-- | Prettyprint Pandoc block element.
prettyBlock :: Block -> String
prettyBlock (BlockQuote blocks) = "BlockQuote\n  " ++ 
                                  (prettyBlockList 2 blocks) 
prettyBlock (OrderedList attribs blockLists) = 
  "OrderedList " ++ show attribs ++ "\n" ++ indentBy 2 0 ("[ " ++ 
  (joinWithSep ", " $ map (\blocks -> prettyBlockList 2 blocks) 
  blockLists)) ++ " ]"
prettyBlock (BulletList blockLists) = "BulletList\n" ++ 
  indentBy 2 0 ("[ " ++ (joinWithSep ", " 
  (map (\blocks -> prettyBlockList 2 blocks) blockLists))) ++ " ]" 
prettyBlock (DefinitionList blockLists) = "DefinitionList\n" ++ 
  indentBy 2 0 ("[" ++ (joinWithSep ",\n" 
  (map (\(term, blocks) -> "  (" ++ show term ++ ",\n" ++ 
  indentBy 1 2 (prettyBlockList 2 blocks) ++ "  )") blockLists))) ++ " ]" 
prettyBlock (Table caption aligns widths header rows) = 
  "Table " ++ show caption ++ " " ++ show aligns ++ " " ++ 
  show widths ++ "\n" ++ prettyRow header ++ " [\n" ++  
  (joinWithSep ",\n" (map prettyRow rows)) ++ " ]"
  where prettyRow cols = indentBy 2 0 ("[ " ++ (joinWithSep ", "
                         (map (\blocks -> prettyBlockList 2 blocks) 
                         cols))) ++ " ]"
prettyBlock block = show block

-- | Prettyprint Pandoc document.
prettyPandoc :: Pandoc -> String
prettyPandoc (Pandoc meta blocks) = "Pandoc " ++ "(" ++ show meta ++ 
  ")\n" ++ (prettyBlockList 0 blocks) ++ "\n"

--
-- Pandoc block and inline list processing
--

-- | Generate infinite lazy list of markers for an ordered list,
-- depending on list attributes.
orderedListMarkers :: (Int, ListNumberStyle, ListNumberDelim) -> [String]
orderedListMarkers (start, numstyle, numdelim) = 
  let singleton c = [c]
      seq = case numstyle of
                    DefaultStyle -> map show [start..]
                    Decimal      -> map show [start..]
                    UpperAlpha   -> drop (start - 1) $ cycle $ 
                                    map singleton ['A'..'Z']
                    LowerAlpha   -> drop (start - 1) $ cycle $
                                    map singleton ['a'..'z']
                    UpperRoman   -> map toRomanNumeral [start..]
                    LowerRoman   -> map (map toLower . toRomanNumeral) [start..]
      inDelim str = case numdelim of
                            DefaultDelim -> str ++ "."
                            Period       -> str ++ "."
                            OneParen     -> str ++ ")"
                            TwoParens    -> "(" ++ str ++ ")"
  in  map inDelim seq

-- | Normalize a list of inline elements: remove leading and trailing
-- @Space@ elements, collapse double @Space@s into singles, and
-- remove empty Str elements.
normalizeSpaces :: [Inline] -> [Inline]
normalizeSpaces [] = []
normalizeSpaces list = 
    let removeDoubles [] = []
        removeDoubles (Space:Space:rest) = removeDoubles (Space:rest)
        removeDoubles (Space:(Str ""):Space:rest) = removeDoubles (Space:rest)
        removeDoubles ((Str ""):rest) = removeDoubles rest 
        removeDoubles (x:rest) = x:(removeDoubles rest)
        removeLeading (Space:xs) = removeLeading xs
        removeLeading x = x
        removeTrailing [] = []
        removeTrailing lst = if (last lst == Space)
                                then init lst
                                else lst
    in  removeLeading $ removeTrailing $ removeDoubles list

-- | Change final list item from @Para@ to @Plain@ if the list should 
-- be compact.
compactify :: [[Block]]  -- ^ List of list items (each a list of blocks)
           -> [[Block]]
compactify [] = []
compactify items =
    let final  = last items
        others = init items
    in  case final of
          [Para a]  -> if any containsPara others
                          then items
                          else others ++ [[Plain a]]
          otherwise -> items

containsPara :: [Block] -> Bool
containsPara [] = False
containsPara ((Para a):rest) = True
containsPara ((BulletList items):rest) =  any containsPara items ||
                                          containsPara rest
containsPara ((OrderedList _ items):rest) = any containsPara items ||
                                            containsPara rest
containsPara ((DefinitionList items):rest) = any containsPara (map snd items) ||
                                             containsPara rest
containsPara (x:rest) = containsPara rest

-- | Data structure for defining hierarchical Pandoc documents
data Element = Blk Block 
             | Sec [Inline] [Element] deriving (Eq, Read, Show)

-- | Returns @True@ on Header block with at least the specified level
headerAtLeast :: Int -> Block -> Bool
headerAtLeast level (Header x _) = x <= level
headerAtLeast level _ = False

-- | Convert list of Pandoc blocks into (hierarchical) list of Elements
hierarchicalize :: [Block] -> [Element]
hierarchicalize [] = []
hierarchicalize (block:rest) = 
  case block of
    (Header level title) -> 
         let (thisSection, rest') = break (headerAtLeast level) rest
         in  (Sec title (hierarchicalize thisSection)):(hierarchicalize rest') 
    x -> (Blk x):(hierarchicalize rest)

-- | True if block is a Header block.
isHeaderBlock :: Block -> Bool
isHeaderBlock (Header _ _) = True
isHeaderBlock _ = False

--
-- Writer options
--

-- | Options for writers
data WriterOptions = WriterOptions
  { writerStandalone      :: Bool   -- ^ Include header and footer
  , writerHeader          :: String -- ^ Header for the document
  , writerTitlePrefix     :: String -- ^ Prefix for HTML titles
  , writerTabStop         :: Int    -- ^ Tabstop for conversion btw spaces and tabs
  , writerTableOfContents :: Bool   -- ^ Include table of contents
  , writerS5              :: Bool   -- ^ We're writing S5 
  , writerUseASCIIMathML  :: Bool   -- ^ Use ASCIIMathML
  , writerASCIIMathMLURL  :: Maybe String -- ^ URL to asciiMathML.js 
  , writerIgnoreNotes     :: Bool   -- ^ Ignore footnotes (used in making toc)
  , writerIncremental     :: Bool   -- ^ Incremental S5 lists
  , writerNumberSections  :: Bool   -- ^ Number sections in LaTeX
  , writerIncludeBefore   :: String -- ^ String to include before the body
  , writerIncludeAfter    :: String -- ^ String to include after the body
  , writerStrictMarkdown  :: Bool   -- ^ Use strict markdown syntax
  , writerReferenceLinks  :: Bool   -- ^ Use reference links in writing markdown, rst
  } deriving Show

-- | Default writer options.
defaultWriterOptions = 
  WriterOptions { writerStandalone      = False,
                  writerHeader          = "",
                  writerTitlePrefix     = "",
                  writerTabStop         = 4,
                  writerTableOfContents = False,
                  writerS5              = False,
                  writerUseASCIIMathML  = False,
                  writerASCIIMathMLURL  = Nothing,
                  writerIgnoreNotes     = False,
                  writerIncremental     = False,
                  writerNumberSections  = False,
                  writerIncludeBefore   = "",
                  writerIncludeAfter    = "",
                  writerStrictMarkdown  = False,
                  writerReferenceLinks  = False }
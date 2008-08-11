{-
Copyright (C) 2006-8 John MacFarlane <jgm@berkeley.edu>

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
   Module      : Text.Pandoc.Readers.LaTeX
   Copyright   : Copyright (C) 2006-8 John MacFarlane
   License     : GNU GPL, version 2 or above 

   Maintainer  : John MacFarlane <jgm@berkeley.edu>
   Stability   : alpha
   Portability : portable

Conversion of LaTeX to 'Pandoc' document.
-}
module Text.Pandoc.Readers.LaTeX ( 
                                  readLaTeX,
                                  rawLaTeXInline,
                                  rawLaTeXEnvironment'
                                 ) where

import Text.ParserCombinators.Parsec
import Text.Pandoc.Definition
import Text.Pandoc.Shared 
import Data.Maybe ( fromMaybe )
import Data.Char ( chr )
import Data.List ( isPrefixOf, isSuffixOf )

-- | Parse LaTeX from string and return 'Pandoc' document.
readLaTeX :: ParserState   -- ^ Parser state, including options for parser
          -> String        -- ^ String to parse
          -> Pandoc
readLaTeX = readWith parseLaTeX

-- characters with special meaning
specialChars :: [Char]
specialChars = "\\`$%^&_~#{}\n \t|<>'\"-"

--
-- utility functions
--

-- | Returns text between brackets and its matching pair.
bracketedText :: Char -> Char -> GenParser Char st [Char]
bracketedText openB closeB = do
  result <- charsInBalanced' openB closeB
  return $ [openB] ++ result ++ [closeB]

-- | Returns an option or argument of a LaTeX command.
optOrArg :: GenParser Char st [Char]
optOrArg = bracketedText '{' '}' <|> bracketedText '[' ']'

-- | True if the string begins with '{'.
isArg :: [Char] -> Bool
isArg ('{':_) = True
isArg _       = False

-- | Returns list of options and arguments of a LaTeX command.
commandArgs :: GenParser Char st [[Char]]
commandArgs = many optOrArg

-- | Parses LaTeX command, returns (name, star, list of options or arguments).
command :: GenParser Char st ([Char], [Char], [[Char]])
command = do
  char '\\'
  name <- many1 letter
  star <- option "" (string "*")  -- some commands have starred versions
  args <- commandArgs
  return (name, star, args)

begin :: [Char] -> GenParser Char st [Char]
begin name = try $ do
  string $ "\\begin{" ++ name ++ "}"
  optional commandArgs
  spaces
  return name

end :: [Char] -> GenParser Char st [Char]
end name = try $ do
  string $ "\\end{" ++ name ++ "}"
  return name

-- | Returns a list of block elements containing the contents of an
-- environment.
environment :: [Char] -> GenParser Char ParserState [Block]
environment name = try $ begin name >> spaces >> manyTill block (end name) >>~ spaces

anyEnvironment :: GenParser Char ParserState Block
anyEnvironment =  try $ do
  string "\\begin{"
  name <- many letter
  star <- option "" (string "*") -- some environments have starred variants
  char '}'
  optional commandArgs
  spaces
  contents <- manyTill block (end (name ++ star))
  spaces
  return $ BlockQuote contents

--
-- parsing documents
--

-- | Process LaTeX preamble, extracting metadata.
processLaTeXPreamble :: GenParser Char ParserState ()
processLaTeXPreamble = try $ manyTill 
  (choice [bibliographic, comment, unknownCommand, nullBlock]) 
  (try (string "\\begin{document}")) >> 
  spaces

-- | Parse LaTeX and return 'Pandoc'.
parseLaTeX :: GenParser Char ParserState Pandoc
parseLaTeX = do
  optional processLaTeXPreamble -- preamble might not be present (fragment)
  spaces
  blocks <- parseBlocks
  spaces
  optional $ try (string "\\end{document}" >> many anyChar) 
  -- might not be present (fragment)
  spaces
  eof
  state <- getState
  let blocks' = filter (/= Null) blocks
  let title' = stateTitle state
  let authors' = stateAuthors state
  let date' = stateDate state
  return $ Pandoc (Meta title' authors' date')  blocks'

--
-- parsing blocks
--

parseBlocks :: GenParser Char ParserState [Block]
parseBlocks = spaces >> many block

block :: GenParser Char ParserState Block
block = choice [ hrule
               , codeBlock
               , header
               , list
               , blockQuote
               , mathBlock
               , comment
               , bibliographic
               , para
               , specialEnvironment
               , itemBlock
               , unknownEnvironment
               , unknownCommand ] <?> "block"

--
-- header blocks
--

header :: GenParser Char ParserState Block
header = try $ do
  char '\\'
  subs <- many (try (string "sub"))
  string "section"
  optional (char '*')
  char '{'
  title' <- manyTill inline (char '}')
  spaces
  return $ Header (length subs + 1) (normalizeSpaces title')

--
-- hrule block
--

hrule :: GenParser Char st Block
hrule = oneOfStrings [ "\\begin{center}\\rule{3in}{0.4pt}\\end{center}\n\n", 
                       "\\newpage" ] >> spaces >> return HorizontalRule

--
-- code blocks
--

codeBlock :: GenParser Char st Block
codeBlock = codeBlock1 <|> codeBlock2

codeBlock1 :: GenParser Char st Block
codeBlock1 = try $ do
  string "\\begin{verbatim}"  -- don't use begin function because it 
                              -- gobbles whitespace
  optional blanklines         -- we want to gobble blank lines, but not 
                              -- leading space
  contents <- manyTill anyChar (try (string "\\end{verbatim}"))
  spaces
  return $ CodeBlock ("",[],[]) (stripTrailingNewlines contents)

codeBlock2 :: GenParser Char st Block
codeBlock2 = try $ do
  string "\\begin{Verbatim}"  -- used by fancyvrb package
  optional blanklines
  contents <- manyTill anyChar (try (string "\\end{Verbatim}"))
  spaces
  return $ CodeBlock ("",[],[]) (stripTrailingNewlines contents)

--
-- block quotes
--

blockQuote :: GenParser Char ParserState Block
blockQuote = (environment "quote" <|> environment "quotation") >>~ spaces >>= 
             return . BlockQuote

--
-- math block
--

mathBlock :: GenParser Char st Block
mathBlock = mathBlockWith (begin "equation") (end "equation") <|> 
            mathBlockWith (begin "displaymath") (end "displaymath") <|>
            mathBlockWith (try $ string "\\[") (try $ string "\\]") <?> 
            "math block"

mathBlockWith :: GenParser Char st t
              -> GenParser Char st end
              -> GenParser Char st Block
mathBlockWith start end' = try $ do
  start
  spaces
  result <- manyTill anyChar end'
  spaces
  return $ BlockQuote [Para [Math result]]

--
-- list blocks
--

list :: GenParser Char ParserState Block
list = bulletList <|> orderedList <|> definitionList <?> "list"

listItem :: GenParser Char ParserState ([Inline], [Block])
listItem = try $ do
  ("item", _, args) <- command
  spaces
  state <- getState
  let oldParserContext = stateParserContext state
  updateState (\s -> s {stateParserContext = ListItemState})
  blocks <- many block
  updateState (\s -> s {stateParserContext = oldParserContext})
  opt <- case args of
           ([x]) | "[" `isPrefixOf` x && "]" `isSuffixOf` x -> 
                       parseFromString (many inline) $ tail $ init x
           _        -> return []
  return (opt, blocks)

orderedList :: GenParser Char ParserState Block
orderedList = try $ do
  string "\\begin{enumerate}"
  (_, style, delim) <- option (1, DefaultStyle, DefaultDelim) $
                              try $ do failIfStrict
                                       char '['
                                       res <- anyOrderedListMarker
                                       char ']'
                                       return res
  spaces
  option "" $ try $ do string "\\setlength{\\itemindent}"
                       char '{'
                       manyTill anyChar (char '}')
  spaces
  start <- option 1 $ try $ do failIfStrict
                               string "\\setcounter{enum"
                               many1 (oneOf "iv")
                               string "}{"
                               num <- many1 digit
                               char '}' 
                               spaces
                               return $ (read num) + 1
  items <- many listItem
  end "enumerate"
  spaces
  return $ OrderedList (start, style, delim) $ map snd items

bulletList :: GenParser Char ParserState Block
bulletList = try $ do
  begin "itemize"
  spaces
  items <- many listItem
  end "itemize"
  spaces
  return (BulletList $ map snd items)

definitionList :: GenParser Char ParserState Block
definitionList = try $ do
  begin "description"
  spaces
  items <- many listItem
  end "description"
  spaces
  return (DefinitionList items)

--
-- paragraph block
--

para :: GenParser Char ParserState Block
para = many1 inline >>~ spaces >>= return . Para . normalizeSpaces

--
-- title authors date
--

bibliographic :: GenParser Char ParserState Block
bibliographic = choice [ maketitle, title, authors, date ]

maketitle :: GenParser Char st Block
maketitle = try (string "\\maketitle") >> spaces >> return Null

title :: GenParser Char ParserState Block
title = try $ do
  string "\\title{"
  tit <- manyTill inline (char '}')
  spaces
  updateState (\state -> state { stateTitle = tit })
  return Null

authors :: GenParser Char ParserState Block
authors = try $ do
  string "\\author{"
  authors' <- manyTill anyChar (char '}')
  spaces
  let authors'' = map removeLeadingTrailingSpace $ lines $
                  substitute "\\\\" "\n" authors'
  updateState (\s -> s { stateAuthors = authors'' })
  return Null

date :: GenParser Char ParserState Block
date = try $ do
  string "\\date{"
  date' <- manyTill anyChar (char '}')
  spaces
  updateState (\state -> state { stateDate = date' })
  return Null

--
-- item block
-- for use in unknown environments that aren't being parsed as raw latex
--

-- this forces items to be parsed in different blocks
itemBlock :: GenParser Char ParserState Block
itemBlock = try $ do
  ("item", _, args) <- command
  state <- getState
  if (stateParserContext state == ListItemState)
     then fail "item should be handled by list block"
     else if null args 
             then return Null
             else return $ Plain [Str (stripFirstAndLast (head args))]

--
-- raw LaTeX 
--

specialEnvironment :: GenParser Char st Block
specialEnvironment = do  -- these are always parsed as raw
  lookAhead (choice (map (\name -> begin name)  ["tabular", "figure",
              "tabbing", "eqnarry", "picture", "table", "verse", "theorem"]))
  rawLaTeXEnvironment

-- | Parse any LaTeX environment and return a Para block containing
-- the whole literal environment as raw TeX.
rawLaTeXEnvironment :: GenParser Char st Block
rawLaTeXEnvironment = do
  contents <- rawLaTeXEnvironment'
  spaces
  return $ Para [TeX contents]

-- | Parse any LaTeX environment and return a string containing
-- the whole literal environment as raw TeX.
rawLaTeXEnvironment' :: GenParser Char st String 
rawLaTeXEnvironment' = try $ do
  string "\\begin{"
  name <- many1 letter
  star <- option "" (string "*") -- for starred variants
  let name' = name ++ star
  char '}'
  args <- option [] commandArgs
  let argStr = concat args
  contents <- manyTill (choice [ (many1 (noneOf "\\")), 
                                 rawLaTeXEnvironment',
                                 string "\\" ]) 
                       (end name')
  return $ "\\begin{" ++ name' ++ "}" ++ argStr ++ 
                 concat contents ++ "\\end{" ++ name' ++ "}"

unknownEnvironment :: GenParser Char ParserState Block
unknownEnvironment = try $ do
  state <- getState
  result <- if stateParseRaw state -- check whether we should include raw TeX 
               then rawLaTeXEnvironment -- if so, get whole raw environment
               else anyEnvironment      -- otherwise just the contents
  return result

unknownCommand :: GenParser Char ParserState Block
unknownCommand = try $ do
  notFollowedBy' $ choice $ map end ["itemize", "enumerate", "description", 
                                     "document"]
  (name, star, args) <- command
  spaces
  let argStr = concat args
  state <- getState
  if name == "item" && (stateParserContext state) == ListItemState
     then fail "should not be parsed as raw"
     else return ""
  if stateParseRaw state
     then return $ Plain [TeX ("\\" ++ name ++ star ++ argStr)]
     else return $ Plain [Str (joinWithSep " " args)]

-- latex comment
comment :: GenParser Char st Block
comment = try $ char '%' >> manyTill anyChar newline >> spaces >> return Null

-- 
-- inline
--

inline :: GenParser Char ParserState Inline
inline =  choice [ str
                 , endline
                 , whitespace
                 , quoted
                 , apostrophe
                 , spacer
                 , strong
                 , math
                 , ellipses
                 , emDash
                 , enDash
                 , hyphen
                 , emph
                 , strikeout
                 , superscript
                 , subscript
                 , ref
                 , lab
                 , code
                 , url
                 , link
                 , image
                 , footnote
                 , linebreak
                 , accentedChar
                 , specialChar
                 , rawLaTeXInline
                 , escapedChar
                 , unescapedChar
                 ] <?> "inline"

accentedChar :: GenParser Char st Inline
accentedChar = normalAccentedChar <|> specialAccentedChar

normalAccentedChar :: GenParser Char st Inline
normalAccentedChar = try $ do
  char '\\'
  accent <- oneOf "'`^\"~"
  character <- (try $ char '{' >> letter >>~ char '}') <|> letter
  let table = fromMaybe [] $ lookup character accentTable 
  let result = case lookup accent table of
                 Just num  -> chr num
                 Nothing   -> '?'
  return $ Str [result]

-- an association list of letters and association list of accents
-- and decimal character numbers.
accentTable :: [(Char, [(Char, Int)])]
accentTable = 
  [ ('A', [('`', 192), ('\'', 193), ('^', 194), ('~', 195), ('"', 196)]),
    ('E', [('`', 200), ('\'', 201), ('^', 202), ('"', 203)]),
    ('I', [('`', 204), ('\'', 205), ('^', 206), ('"', 207)]),
    ('N', [('~', 209)]),
    ('O', [('`', 210), ('\'', 211), ('^', 212), ('~', 213), ('"', 214)]),
    ('U', [('`', 217), ('\'', 218), ('^', 219), ('"', 220)]),
    ('a', [('`', 224), ('\'', 225), ('^', 227), ('"', 228)]),
    ('e', [('`', 232), ('\'', 233), ('^', 234), ('"', 235)]),
    ('i', [('`', 236), ('\'', 237), ('^', 238), ('"', 239)]),
    ('n', [('~', 241)]),
    ('o', [('`', 242), ('\'', 243), ('^', 244), ('~', 245), ('"', 246)]),
    ('u', [('`', 249), ('\'', 250), ('^', 251), ('"', 252)]) ]

specialAccentedChar :: GenParser Char st Inline
specialAccentedChar = choice [ ccedil, aring, iuml, szlig, aelig,
                               oslash, pound, euro, copyright, sect ]

ccedil :: GenParser Char st Inline
ccedil = try $ do
  char '\\'
  letter' <- oneOfStrings ["cc", "cC"]
  let num = if letter' == "cc" then 231 else 199
  return $ Str [chr num]

aring :: GenParser Char st Inline
aring = try $ do
  char '\\'
  letter' <- oneOfStrings ["aa", "AA"]
  let num = if letter' == "aa" then 229 else 197
  return $ Str [chr num]

iuml :: GenParser Char st Inline
iuml = try (string "\\\"") >> oneOfStrings ["\\i", "{\\i}"] >> 
       return (Str [chr 239])

szlig :: GenParser Char st Inline
szlig = try (string "\\ss") >> return (Str [chr 223])

oslash :: GenParser Char st Inline
oslash = try $ do
  char '\\'
  letter' <- choice [char 'o', char 'O']
  let num = if letter' == 'o' then 248 else 216
  return $ Str [chr num]

aelig :: GenParser Char st Inline
aelig = try $ do
  char '\\'
  letter' <- oneOfStrings ["ae", "AE"]
  let num = if letter' == "ae" then 230 else 198
  return $ Str [chr num]

pound :: GenParser Char st Inline
pound = try (string "\\pounds") >> return (Str [chr 163])

euro :: GenParser Char st Inline
euro = try (string "\\euro") >> return (Str [chr 8364])

copyright :: GenParser Char st Inline
copyright = try (string "\\copyright") >> return (Str [chr 169])

sect :: GenParser Char st Inline
sect = try (string "\\S") >> return (Str [chr 167])

escapedChar :: GenParser Char st Inline
escapedChar = do
  result <- escaped (oneOf " $%&_#{}\n")
  return $ if result == Str "\n" then Str " " else result

-- ignore standalone, nonescaped special characters
unescapedChar :: GenParser Char st Inline
unescapedChar = oneOf "`$^&_#{}|<>" >> return (Str "")

specialChar :: GenParser Char st Inline
specialChar = choice [ backslash, tilde, caret, bar, lt, gt, doubleQuote ]

backslash :: GenParser Char st Inline
backslash = try (string "\\textbackslash") >> return (Str "\\")

tilde :: GenParser Char st Inline
tilde = try (string "\\ensuremath{\\sim}") >> return (Str "~")

caret :: GenParser Char st Inline
caret = try (string "\\^{}") >> return (Str "^")

bar :: GenParser Char st Inline
bar = try (string "\\textbar") >> return (Str "\\")

lt :: GenParser Char st Inline
lt = try (string "\\textless") >> return (Str "<")

gt :: GenParser Char st Inline
gt = try (string "\\textgreater") >> return (Str ">")

doubleQuote :: GenParser Char st Inline
doubleQuote = char '"' >> return (Str "\"")

code :: GenParser Char st Inline
code = code1 <|> code2

code1 :: GenParser Char st Inline
code1 = try $ do 
  string "\\verb"
  marker <- anyChar
  result <- manyTill anyChar (char marker)
  return $ Code $ removeLeadingTrailingSpace result

code2 :: GenParser Char st Inline
code2 = try $ do
  string "\\texttt{"
  result <- manyTill (noneOf "\\\n~$%^&{}") (char '}')
  return $ Code result

emph :: GenParser Char ParserState Inline
emph = try $ oneOfStrings [ "\\emph{", "\\textit{" ] >>
             manyTill inline (char '}') >>= return . Emph

strikeout :: GenParser Char ParserState Inline
strikeout = try $ string "\\sout{" >> manyTill inline (char '}') >>=
                  return . Strikeout

superscript :: GenParser Char ParserState Inline
superscript = try $ string "\\textsuperscript{" >> 
                    manyTill inline (char '}') >>= return . Superscript

-- note: \textsubscript isn't a standard latex command, but we use
-- a defined version in pandoc.
subscript :: GenParser Char ParserState Inline
subscript = try $ string "\\textsubscript{" >> manyTill inline (char '}') >>=
                  return . Subscript

apostrophe :: GenParser Char ParserState Inline
apostrophe = char '\'' >> return Apostrophe

quoted :: GenParser Char ParserState Inline
quoted = doubleQuoted <|> singleQuoted

singleQuoted :: GenParser Char ParserState Inline
singleQuoted = enclosed singleQuoteStart singleQuoteEnd inline >>=
               return . Quoted SingleQuote . normalizeSpaces

doubleQuoted :: GenParser Char ParserState Inline
doubleQuoted = enclosed doubleQuoteStart doubleQuoteEnd inline >>=
               return . Quoted DoubleQuote . normalizeSpaces

singleQuoteStart :: GenParser Char st Char
singleQuoteStart = char '`'

singleQuoteEnd :: GenParser Char st ()
singleQuoteEnd = try $ char '\'' >> notFollowedBy alphaNum

doubleQuoteStart :: CharParser st String
doubleQuoteStart = string "``"

doubleQuoteEnd :: CharParser st String
doubleQuoteEnd = try $ string "''"

ellipses :: GenParser Char st Inline
ellipses = try $ string "\\ldots" >> optional (try (string "{}")) >>
                 return Ellipses

enDash :: GenParser Char st Inline
enDash = try (string "--") >> return EnDash

emDash :: GenParser Char st Inline
emDash = try (string "---") >> return EmDash

hyphen :: GenParser Char st Inline
hyphen = char '-' >> return (Str "-")

lab :: GenParser Char st Inline
lab = try $ do
  string "\\label{"
  result <- manyTill anyChar (char '}')
  return $ Str $ "(" ++ result ++ ")"

ref :: GenParser Char st Inline
ref = try (string "\\ref{") >> manyTill anyChar (char '}') >>= return . Str

strong :: GenParser Char ParserState Inline
strong = try (string "\\textbf{") >> manyTill inline (char '}') >>=
         return . Strong

whitespace :: GenParser Char st Inline
whitespace = many1 (oneOf "~ \t") >> return Space

-- hard line break
linebreak :: GenParser Char st Inline
linebreak = try (string "\\\\") >> return LineBreak

spacer :: GenParser Char st Inline
spacer = try (string "\\,") >> return (Str "")

str :: GenParser Char st Inline
str = many1 (noneOf specialChars) >>= return . Str

-- endline internal to paragraph
endline :: GenParser Char st Inline
endline = try $ newline >> notFollowedBy blankline >> return Space

-- math
math :: GenParser Char st Inline
math = math1 <|> math2 <?> "math"

math1 :: GenParser Char st Inline
math1 = try $ do
  char '$'
  result <- many (noneOf "$")
  char '$'
  return $ Math result

math2 :: GenParser Char st Inline
math2 = try $ do
  string "\\("
  result <- many (noneOf "$")
  string "\\)"
  return $ Math result

--
-- links and images
--

url :: GenParser Char ParserState Inline
url = try $ do
  string "\\url"
  url' <- charsInBalanced '{' '}'
  return $ Link [Code url'] (url', "")

link :: GenParser Char ParserState Inline
link = try $ do
  string "\\href{"
  url' <- manyTill anyChar (char '}')
  char '{'
  label' <- manyTill inline (char '}') 
  return $ Link (normalizeSpaces label') (url', "")

image :: GenParser Char ParserState Inline
image = try $ do
  ("includegraphics", _, args) <- command
  let args' = filter isArg args -- filter out options
  let src = if null args' then
              ("", "")
            else
              (stripFirstAndLast (head args'), "")
  return $ Image [Str "image"] src

footnote :: GenParser Char ParserState Inline
footnote = try $ do
  (name, _, (contents:[])) <- command
  if ((name == "footnote") || (name == "thanks"))
     then string ""
     else fail "not a footnote or thanks command"
  let contents' = stripFirstAndLast contents
  -- parse the extracted block, which may contain various block elements:
  rest <- getInput
  setInput $ contents'
  blocks <- parseBlocks
  setInput rest
  return $ Note blocks

-- | Parse any LaTeX command and return it in a raw TeX inline element.
rawLaTeXInline :: GenParser Char ParserState Inline
rawLaTeXInline = try $ do
  (name, star, args) <- command
  state <- getState
  if ((name == "begin") || (name == "end") || (name == "item"))
     then fail "not an inline command" 
     else string ""
  if stateParseRaw state
     then return $ TeX ("\\" ++ name ++ star ++ concat args)
     else return $ Str (joinWithSep " " args)


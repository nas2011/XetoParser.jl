@enum TokenKind begin
    # Core
    TOK_EOF
    TOK_ERROR
    TOK_NEWLINE
    TOK_COMMENT
    
    # Literals & Identifiers
    TOK_IDENTIFIER
    TOK_NUMBER
    TOK_STRING
    TOK_REF
    
    # Symbols / Punctuation
    TOK_COLON         # :
    TOK_DOUBLE_COLON  # ::
    TOK_PLUS          # +
    TOK_LANGLE        # <
    TOK_RANGLE        # >
    TOK_LBRACE        # {
    TOK_RBRACE        # }
    TOK_COMMA         # ,
    TOK_QUESTION      # ?
    TOK_AMPERSAND     # &
    TOK_PIPE          # |
    TOK_DOT           # .
    TOK_ASTERISK      # *
end

struct Token
    kind::TokenKind
    lexeme::String
    line::Int
    col::Int
end

mutable struct Lexer
    chars::Vector{Char}
    pos::Int
    len::Int
    line::Int
    col::Int
end

function Lexer(input::String)
    chars = collect(input)
    Lexer(chars, 1, length(chars), 1, 1)
end

# --- Helper Functions ---

function peek(l::Lexer, offset::Int = 0)::Char
    idx = l.pos + offset
    idx <= l.len ? l.chars[idx] : '\0'
end

function advance!(l::Lexer)::Char
    ch = peek(l)
    l.pos += 1
    if ch == '\n'
        l.line += 1
        l.col = 1
    else
        l.col += 1
    end
    return ch
end

function isEof(l::Lexer)::Bool
    l.pos > l.len
end


function nextToken!(l::Lexer)::Token
    # Skip non-newline whitespace
    while !isEof(l) && peek(l) in (' ', '\t', '\r')
        advance!(l)
    end

    if isEof(l)
        return Token(TOK_EOF, "", l.line, l.col)
    end

    startLine = l.line
    startCol = l.col
    ch = peek(l)

    # 1. Newlines
    if ch == '\n'
        advance!(l)
        return Token(TOK_NEWLINE, "\n", startLine, startCol)
    end

    # 2. Comments (// to end of line)
    if ch == '/' && peek(l, 1) == '/'
        lexeme = ""
        while !isEof(l) && peek(l) != '\n'
            lexeme *= advance!(l)
        end
        return Token(TOK_COMMENT, lexeme, startLine, startCol)
    end

    # 3. Symbols & Punctuation
    symbols = Dict(
        '+' => TOK_PLUS, '<' => TOK_LANGLE, '>' => TOK_RANGLE,
        '{' => TOK_LBRACE, '}' => TOK_RBRACE, ',' => TOK_COMMA,
        '?' => TOK_QUESTION, '&' => TOK_AMPERSAND, '|' => TOK_PIPE,
        '.' => TOK_DOT, '*' => TOK_ASTERISK
    )
    
    if haskey(symbols, ch)
        advance!(l)
        return Token(symbols[ch], string(ch), startLine, startCol)
    end

    # Handle : vs ::
    if ch == ':'
        advance!(l)
        if peek(l) == ':'
            advance!(l)
            return Token(TOK_DOUBLE_COLON, "::", startLine, startCol)
        end
        return Token(TOK_COLON, ":", startLine, startCol)
    end

    # 4. References (@...)
    if ch == '@'
        advance!(l) # Consume '@'
        lexeme = "@"
        # refChar := alpha | digit | "_" | "~" | ":" | "-"
        while !isEof(l)
            nc = peek(l)
            if isletter(nc) || isdigit(nc) || nc in ('_', '~')
                lexeme *= advance!(l)
            else
                break
            end
        end
        return Token(TOK_REF, lexeme, startLine, startCol)
    end

    # 5. Heredocs (--- ... ---)
    if ch == '-' && peek(l, 1) == '-' && peek(l, 2) == '-'
        advance!(l); advance!(l); advance!(l)
        lexeme = "---"
        while !isEof(l)
            if peek(l) == '-' && peek(l, 1) == '-' && peek(l, 2) == '-'
                lexeme *= advance!(l); lexeme *= advance!(l); lexeme *= advance!(l)
                break
            end
            lexeme *= advance!(l)
        end
        return Token(TOK_STRING, lexeme, startLine, startCol)
    end

    # 6. Numbers (starts with digit or '-' followed by digit)
    if isdigit(ch) || (ch == '-' && isdigit(peek(l, 1)))
        lexeme = string(advance!(l))
        # Match ASCII digit/letter, ., -, :, /, $, %, or any Unicode > 0x7F
        while !isEof(l)
            nc = peek(l)
            if isletter(nc) || isdigit(nc) || nc in ('.', '-', ':', '/', '$', '%') || Int(nc) > 0x7F
                lexeme *= advance!(l)
            else
                break
            end
        end
        return Token(TOK_NUMBER, lexeme, startLine, startCol)
    end

    # 7. Identifiers (Starts with alpha, continues with alpha, digit, _)
    if isletter(ch)
        lexeme = string(advance!(l))
        while !isEof(l)
            nc = peek(l)
            if isletter(nc) || isdigit(nc) || nc == '_'
                lexeme *= advance!(l)
            else
                break
            end
        end
        return Token(TOK_IDENTIFIER, lexeme, startLine, startCol)
    end

    # 8. Strings ("hi", """hi""", 'hi')
    if ch == '"' || ch == '\''
        quoteChar = advance!(l)
        isTriple = false
        lexeme = string(quoteChar)
        
        # Check for triple quote
        if quoteChar == '"' && peek(l) == '"' && peek(l, 1) == '"'
            isTriple = true
            lexeme *= advance!(l)
            lexeme *= advance!(l)
        end
        
        while !isEof(l)
            nc = advance!(l)
            lexeme *= nc
            
            if nc == '\\' && !isTriple # Handle escapes if not triple
                if !isEof(l) lexeme *= advance!(l) end
                continue
            end
            
            if isTriple
                if nc == '"' && peek(l) == '"' && peek(l, 1) == '"'
                    lexeme *= advance!(l)
                    lexeme *= advance!(l)
                    break
                end
            elseif nc == quoteChar
                break
            end
        end
        return Token(TOK_STRING, lexeme, startLine, startCol)
    end

    # 9. Fallback Error
    badChar = advance!(l)
    return Token(TOK_ERROR, string(badChar), startLine, startCol)
end

function tokenize(input::String)::Vector{Token}
    lexer = Lexer(input)
    tokens = Token[]
    while true
        tok = nextToken!(lexer)
        push!(tokens, tok)
        if tok.kind == TOK_EOF
            break
        end
    end
    return tokens
end


mutable struct Parser
    tokens::Vector{Token}
    pos::Int
end

function Parser(tokens::Vector{Token})
    Parser(tokens, 1)
end

# --- Utility Functions ---

"""Returns the token at the current position plus the given offset."""
function peek(p::Parser, offset::Int = 0)::Token
    idx = p.pos + offset
    if idx > length(p.tokens)
        return p.tokens[end] # Should safely return TOK_EOF
    end
    return p.tokens[idx]
end

"""Checks if we have reached the end of the token stream."""
function isAtEnd(p::Parser)::Bool
    peek(p).kind == TOK_EOF
end

"""Checks if the current token matches the given kind without consuming it."""
function check(p::Parser, kind::TokenKind)::Bool
    if isAtEnd(p) return false end
    return peek(p).kind == kind
end

"""Consumes the current token and advances the position."""
function advance!(p::Parser)::Token
    if !isAtEnd(p)
        p.pos += 1
    end
    return peek(p, -1)
end

"""Consumes the token if it matches any of the given kinds."""
function match!(p::Parser, kinds::TokenKind...)::Bool
    for kind in kinds
        if check(p, kind)
            advance!(p)
            return true
        end
    end
    return false
end

"""Requires the current token to be of a specific kind, throwing an error if not."""
function consume!(p::Parser, kind::TokenKind, errMsg::String)::Token
    if check(p, kind)
        return advance!(p)
    end
    tok = peek(p)
    error("Parse error at line $(tok.line), col $(tok.col): $errMsg. Found $(tok.kind) ('$(tok.lexeme)')")
end

# --- Parsing Logic ---

"""
Parses the root <libFile> rule:
<libFile> := [<typeDef> | <mixinDef> | <instance>]*
"""
function parseLibFile!(p::Parser)::LibFile
    defs = DefNode[]
    
    while !isAtEnd(p)
        # Safely eat stray newlines or comments at the top level
        if match!(p, TOK_NEWLINE, TOK_COMMENT)
            continue
        end
        
        if check(p, TOK_PLUS)
            push!(defs, parseMixinDef!(p))
            
        elseif check(p, TOK_REF)
            push!(defs, parseInstance!(p))
            
        elseif check(p, TOK_IDENTIFIER)
            push!(defs, parseTypeDef!(p))
            
        else
            tok = peek(p)
            error("Unexpected token at top level: '$(tok.lexeme)' at line $(tok.line)")
        end
    end
    
    return LibFile(defs)
end

# --- Stubs for Top-Level Definitions ---

function parseTypeDef!(p::Parser)::TypeDef
    # <typeDef> := <name> ":" <spec> <nl>
    nameTok = consume!(p, TOK_IDENTIFIER, "Expected type name")
    consume!(p, TOK_COLON, "Expected ':' after type name")
    
    spec = parseSpec!(p)
    
    # Consume the required newline (or tolerate EOF if it's the last line)
    if !isAtEnd(p)
        consume!(p, TOK_NEWLINE, "Expected newline after type definition")
    end
    
    return TypeDef(Name(nameTok.lexeme), spec)
end

# function parseSpec!(p::Parser)::Spec
#     # <spec> := [<type> [<meta>]] <specBody>
    
#     local t::Union{TypeNode, Nothing} = nothing
#     local m::Union{Meta, Nothing} = nothing
    
#     # If it starts with an identifier, it MUST be a <type>
#     if check(p, TOK_IDENTIFIER)
#         t = parseType!(p)
        
#         # Check for optional <meta>
#         if check(p, TOK_LANGLE) # '<'
#             m = parseMeta!(p)
#         end
#     end
    
#     body = parseSpecBody!(p)
    
#     return Spec(t, m, body)
# end

function parseSpec!(p::Parser)::Spec
    # <spec> := [<type> [<meta>]] <specBody> // must have at least one
    
    local t::Union{TypeNode, Nothing} = nothing
    local m::Union{Meta, Nothing} = nothing
    local body::Union{SpecBodyNode, Nothing} = nothing
    
    # 1. Check for optional Type
    if check(p, TOK_IDENTIFIER)
        t = parseType!(p)
        
        # Check for optional Meta
        if check(p, TOK_LANGLE) # '<'
            m = parseMeta!(p)
        end
    end
    
    # 2. Check for optional Body
    # A SpecBody is either SpecSlots (starts with '{') or a SpecVal (scalar: string, number, ref)
    if check(p, TOK_LBRACE) || check(p, TOK_STRING) || check(p, TOK_NUMBER) || check(p, TOK_REF)
        body = parseSpecBody!(p)
    end
    
    # 3. Enforce the "must have at least one" rule
    if t === nothing && body === nothing
        tok = peek(p)
        error("Parse error at line $(tok.line): Spec must have a type or a body. Found '$(tok.lexeme)'")
    end
    
    return Spec(t, m, body)
end

function parseSpecBody!(p::Parser)::SpecBodyNode
    # <specBody> := <specSlots> | <specVal>
    if check(p, TOK_LBRACE) # '{'
        return parseSpecSlots!(p)
    else
        return parseSpecVal!(p)
    end
end

function parseType!(p::Parser)::TypeNode
    # <type> := <typeMaybe> | <typeAnd> | <typeOr> | <typeSimple>
    
    baseType = TypeSimple(parseQname!(p))
    
    if match!(p, TOK_QUESTION)
        return TypeMaybe(baseType)
        
    elseif check(p, TOK_AMPERSAND)
        types = [baseType]
        while match!(p, TOK_AMPERSAND)
            push!(types, TypeSimple(parseQname!(p)))
        end
        return TypeAnd(types)
        
    elseif check(p, TOK_PIPE)
        types = [baseType]
        while match!(p, TOK_PIPE)
            push!(types, TypeSimple(parseQname!(p)))
        end
        return TypeOr(types)
    end
    
    return baseType
end

function parseSpecVal!(p::Parser)::SpecVal
    # <specVal> := <scalar>
    tok = advance!(p)
    
    # Based on the scalar definition in the BNF
    if tok.kind in (TOK_STRING, TOK_NUMBER, TOK_REF)
        return SpecVal(Scalar(tok.lexeme))
    else
        error("Parse error at line $(tok.line): Expected scalar value, got '$(tok.lexeme)'")
    end
end

function parseQname!(p::Parser)::QName
    # <qname> := [<dottedName> "::"] <dottedName>
    # <dottedName> := <name> ("." <name>)*
    
    modules = String[]
    nameTok = consume!(p, TOK_IDENTIFIER, "Expected identifier in type name")
    currentName = nameTok.lexeme
    
    # Loop to capture module boundaries (::) and dot notation (.)
    while check(p, TOK_DOUBLE_COLON) || check(p, TOK_DOT)
        if match!(p, TOK_DOUBLE_COLON) || match!(p, TOK_DOT)
            push!(modules, currentName)
            currentName = consume!(p, TOK_IDENTIFIER, "Expected identifier after '::' or '.'").lexeme
        end
    end
    
    return QName(modules, currentName)
end

function parseMixinDef!(p::Parser)::MixinDef
    # <mixinDef> := "+" <type> ":" [<meta>] [<specSlots>] <nl>
    consume!(p, TOK_PLUS, "Expected '+' for mixin definition")
    
    mixinType = parseType!(p)
    consume!(p, TOK_COLON, "Expected ':' after mixin type")
    
    local meta::Union{Meta, Nothing} = nothing
    if check(p, TOK_LANGLE)
        meta = parseMeta!(p)
    end
    
    local slots::Union{SpecSlots, Nothing} = nothing
    if check(p, TOK_LBRACE)
        slots = parseSpecSlots!(p)
    end
    
    if !isAtEnd(p)
        consume!(p, TOK_NEWLINE, "Expected newline after mixin definition")
    end
    
    return MixinDef(mixinType, meta, slots)
end

function parseInstance!(p::Parser)::InstanceDef
    # <instance> := <ref> ":" <dict> <nl>
    refTok = consume!(p, TOK_REF, "Expected reference for instance")
    consume!(p, TOK_COLON, "Expected ':' after instance reference")
    
    dict = parseDict!(p)
    
    if !isAtEnd(p)
        consume!(p, TOK_NEWLINE, "Expected newline after instance definition")
    end
    
    return InstanceDef(RefNode(refTok.lexeme, nothing), dict)
end

function parseDict!(p::Parser)::DictNode
    # <dict> := [<dataType>] "{" <dictTags> "}"
    local datatype::Union{TypeSimple, Nothing} = nothing
    
    if check(p, TOK_IDENTIFIER)
        datatype = TypeSimple(parseQname!(p))
    end
    
    consume!(p, TOK_LBRACE, "Expected '{' to start dict")
    tags = parseDictTags!(p, TOK_RBRACE)
    consume!(p, TOK_RBRACE, "Expected '}' to end dict")
    
    return DictNode(datatype, tags)
end

function parseMeta!(p::Parser)::Meta
    # <meta> := "<" <dictTags> ">"
    consume!(p, TOK_LANGLE, "Expected '<' to start meta")
    tags = parseDictTags!(p, TOK_RANGLE)
    consume!(p, TOK_RANGLE, "Expected '>' to end meta")
    return Meta(tags)
end

function parseDictTags!(p::Parser, endTok::TokenKind)::Vector{DictTagNode}
    tags = DictTagNode[]
    while !isAtEnd(p) && !check(p, endTok)
        if match!(p, TOK_NEWLINE) continue end # Skip empty lines
        
        push!(tags, parseDictTag!(p))
        
        # <endOfObj> := ( [","] <nl> ) | ","
        if match!(p, TOK_COMMA)
            match!(p, TOK_NEWLINE)
        else
            match!(p, TOK_NEWLINE)
        end
    end
    return tags
end

function parseDictTag!(p::Parser)::DictTagNode
    # <dictTag> := <dictMarkerTag> | <dictNamedTag> | <dictUnnamedTag> | <dictIdTag> | <dictNamedIdTag>
    
    if check(p, TOK_IDENTIFIER)
        # Lookahead to distinguish NamedTag, NamedIdTag, and MarkerTag
        nameTok = peek(p)
        nextTok = peek(p, 1)
        
        if nextTok.kind == TOK_COLON
            advance!(p) # consume name
            advance!(p) # consume ':'
            return DictNamedTag(Name(nameTok.lexeme), parseData!(p))
        elseif nextTok.kind == TOK_REF
            advance!(p) # consume name
            refTok = advance!(p) # consume ref
            consume!(p, TOK_COLON, "Expected ':' after ref in DictNamedIdTag")
            return DictNamedIdTag(Name(nameTok.lexeme), RefNode(refTok.lexeme, nothing), parseDict!(p))
        else
            advance!(p) # consume name
            return DictMarkerTag(Name(nameTok.lexeme))
        end
        
    elseif check(p, TOK_REF)
        refTok = advance!(p)
        consume!(p, TOK_COLON, "Expected ':' after ref in DictIdTag")
        return DictIdTag(RefNode(refTok.lexeme, nothing), parseDict!(p))
        
    else
        return DictUnnamedTag(parseData!(p))
    end
end

function parseData!(p::Parser)::DataNode
    # <data> := <dict> | <dataScalar> | <ref> | <spec>
    if check(p, TOK_LBRACE) || (check(p, TOK_IDENTIFIER) && peek(p, 1).kind == TOK_LBRACE)
        return parseDict!(p)
    elseif check(p, TOK_IDENTIFIER) || check(p, TOK_LANGLE)
        # If it starts with an identifier not followed by '{', or starts with '<', it's a Spec
        return parseSpec!(p)
    else
        # <dataScalar> := [<dataType>] <scalar>
        local datatype::Union{TypeSimple, Nothing} = nothing
        # Note: robust scalar/datatype disambiguation requires checking if the identifier is a type vs a string
        tok = advance!(p)
        return DataScalar(datatype, Scalar(tok.lexeme))
    end
end

function parseSpecSlots!(p::Parser)::SpecSlots
    consume!(p, TOK_LBRACE, "Expected '{' to start spec slots")
    slots = SpecSlotNode[]
    
    while !isAtEnd(p) && !check(p, TOK_RBRACE)
        if match!(p, TOK_NEWLINE) continue end
        
        push!(slots, parseSpecSlot!(p))
        
        # <endOfObj>
        if match!(p, TOK_COMMA)
            match!(p, TOK_NEWLINE)
        else
            match!(p, TOK_NEWLINE)
        end
    end
    
    consume!(p, TOK_RBRACE, "Expected '}' to end spec slots")
    return SpecSlots(slots)
end

function parseSpecSlot!(p::Parser)::SpecSlotNode
    # <specSlot> := [<leadingDoc>] ( <markerSlot> | <namedSlot> | <unnamedSlot> | <inlineMeta>) [<trailingDoc>]
    
    leadingDoc = String[]
    while check(p, TOK_COMMENT)
        push!(leadingDoc, advance!(p).lexeme)
        match!(p, TOK_NEWLINE)
    end
    
    globalPrefix = match!(p, TOK_ASTERISK)
    
    local slot::SpecSlotNode
    
    if check(p, TOK_LANGLE)
        # <inlineMeta>
        tags = parseMeta!(p).tags
        slot = InlineMetaSlot(tags, leadingDoc, nothing)
        
    elseif check(p, TOK_IDENTIFIER)
        nameTok = peek(p)
        if peek(p, 1).kind == TOK_COLON
            # <namedSlot>
            advance!(p) # consume name
            advance!(p) # consume ':'
            slot = NamedSlot(globalPrefix, Name(nameTok.lexeme), parseSpec!(p), leadingDoc, nothing)
        elseif isletter(nameTok.lexeme[1]) && islowercase(nameTok.lexeme[1])
            # <markerSlot> := [<globalPrefix>] <markerName> [<meta>]
            advance!(p)
            local meta::Union{Meta, Nothing} = nothing
            if check(p, TOK_LANGLE)
                meta = parseMeta!(p)
            end
            slot = MarkerSlot(globalPrefix, Name(nameTok.lexeme), meta, leadingDoc, nothing)
        else
            # Must be an <unnamedSlot> starting with a Type
            slot = UnnamedSlot(parseSpec!(p), leadingDoc, nothing)
        end
        
    else
        # <unnamedSlot>
        slot = UnnamedSlot(parseSpec!(p), leadingDoc, nothing)
    end
    
    # Check for trailing doc
    if check(p, TOK_COMMENT)
        # Note: Because structs are immutable in Julia by default, we'd normally recreate the struct here 
        # or use mutable structs. For brevity, assuming the AST structs are defined to allow this or we 
        # rebuild them right here.
        trailingDoc = advance!(p).lexeme
        # Rebuild struct with trailing doc (pseudo-code depending on exact AST implementation)
        # slot = rebuildWithTrailing(slot, trailingDoc)
    end
    
    return slot
end


"""
Normalizes a triple-quoted string or heredoc token according to Xeto rules.
`lexeme` is the raw token string (e.g., \"\"\"\\n  hello\\n  \"\"\").
`isHeredoc` should be true if the delimiter is `---`.
"""
function normalizeMultiline(lexeme::String, isHeredoc::Bool)::String
    delimiterLen = 3
    
    # 1. Strip the outer delimiters (""" or ---)
    if length(lexeme) >= 6
        content = lexeme[(delimiterLen + 1):(end - delimiterLen)]
    else
        return "" # Edge case: empty """""" or ------
    end

    lines = split(content, '\n')

    # 2. Rule: If opening line is empty, skip it.
    # Because we split by '\n', a leading newline makes the first element empty "" or pure spaces.
    if !isempty(lines) && all(isspace, lines[1])
        popfirst!(lines)
    end

    # 3. Calculate inferred indentation
    # Based on the left-most non-empty line OR the closing quote's indentation.
    # (The last element in `lines` is the text right before the closing delimiter).
    minIndent = typemax(Int)
    
    for (i, line) in enumerate(lines)
        # We check non-empty lines, PLUS we always check the very last line 
        # because it dictates the closing quote's indentation.
        if !all(isspace, line) || i == length(lines)
            spaces = 0
            for ch in line
                if ch == ' '
                    spaces += 1
                else
                    break
                end
            end
            minIndent = min(minIndent, spaces)
        end
    end
    
    if minIndent == typemax(Int)
        minIndent = 0
    end

    # 4. Trim leading spaces
    normalizedLines = String[]
    for (i, line) in enumerate(lines)
        # If the last line is purely the spaces used to indent the closing quote, drop it.
        if i == length(lines) && all(isspace, line)
            continue
        end
        
        # Safely slice the string, respecting unicode character boundaries
        startIdx = nextind(line, 0, minIndent + 1)
        if startIdx <= ncodeunits(line)
            push!(normalizedLines, line[startIdx:end])
        else
            push!(normalizedLines, "") # Line was shorter than minIndent (e.g., empty)
        end
    end

    normalizedContent = join(normalizedLines, "\n")

    # 5. Handle escape sequences
    # Heredocs ignore backslash escapes; triple quotes evaluate them.
    if !isHeredoc
        # Julia's built-in unescapeString handles standard C-style escapes (\n, \\, \", \u)
        normalizedContent = unescapeString(normalizedContent)
    end

    return normalizedContent
end


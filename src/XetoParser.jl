module XetoParser

    include("Tokenizer.jl")
    include("StringNormalizer.jl")
    include("XetoAST.jl")
    include("Parser.jl")
    include("ToJSONSchema.jl")

    export 
        tokenize,
        Parser,
        parseLibFile!,
        convertTypedefToJsonschema# Write your package code here.
end

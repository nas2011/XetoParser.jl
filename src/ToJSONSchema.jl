function typeToJsonschema(typeNode::TypeNode)::Dict{String, Any}
    schema = Dict{String, Any}()
    
    if typeNode isa TypeSimple
        name = typeNode.qname.name
        if name == "Str"
            schema["type"] = "string"
        elseif name == "Number"
            schema["type"] = "number" # Or "number" depending on precision
        elseif name == "Bool"
            schema["type"] = "boolean"
        elseif name == "Dict"
            schema["type"] = "object"
        else
            # For custom types, you might use $ref in JSON Schema
            schema["\$ref"] = "#/definitions/$name"
        end
    elseif typeNode isa TypeMaybe
        # In JSON Schema, optional types just aren't listed in the "required" array of the parent object.
        # But we can still resolve the base type here.
        schema = typeToJsonschema(typeNode.base)
    end
    
    return schema
end

function specToJsonschema(spec::Spec)::Dict{String, Any}
    schema = Dict{String, Any}()
    
    # 1. Resolve the base type (if any)
    if spec.type !== nothing
        merge!(schema, typeToJsonschema(spec.type))
    end
    
    # 2. Resolve nested properties if it has a body with slots
    if spec.body isa SpecSlots
        schema["type"] = "object" # Force object type if it has slots
        properties = Dict{String, Any}()
        required = String[]
        
        for slot in spec.body.slots
            if slot isa NamedSlot
                slotName = slot.name.val
                properties[slotName] = specToJsonschema(slot.spec)
                
                # If the type is NOT a TypeMaybe (e.g., String?), it's required
                if slot.spec.type === nothing || !(slot.spec.type isa TypeMaybe)
                    push!(required, slotName)
                end
                
                # Optional: Add leading doc as description
                if !isempty(slot.leadingDoc)
                    properties[slotName]["description"] = join(strip.(slot.leadingDoc), "\n")
                end
            end
        end
        
        schema["properties"] = properties
        if !isempty(required)
            schema["required"] = required
        end
    end
    
    return schema
end

function convertTypedefToJsonschema(typedef::TypeDef)::Dict{String, Any}
    schema = specToJsonschema(typedef.spec)
    schema["title"] = typedef.name.val
    schema["\$schema"] = "http://json-schema.org/draft-07/schema#"
    return schema
end
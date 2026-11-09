return function(value, total)
    if
        type(value) == "number"
        and type(total) == "number"
        and value == value
        and total > 0
        and math.abs(value) ~= math.huge
        and total ~= math.huge
    then
        return math.max(0, math.min(1, value / total))
    end
end

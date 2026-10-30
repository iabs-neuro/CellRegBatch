function order = natural_order(names)
%NATURAL_ORDER Sort order of names with numbers compared by value.
%   names: cellstr. order: index vector, names(order) is sorted. Digit runs
%   compare as numbers, so '2D' comes before '10D' and 'M9' before 'M10'.
%   Up to 20 digits per number.
    keys = regexprep(names, '\d+', '${[repmat(''0'', 1, 20 - numel($0)) $0]}');
    [~, order] = sort(keys);
end

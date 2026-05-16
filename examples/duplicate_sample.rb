def alpha(xs)
  kept = xs.select { |item| item.odd? }
  sorted = kept.sort_by { |item| item.to_s }
  sorted.map { |item| item + 1 }
end

def beta(rows)
  closed = rows.select { |row| row.even? }
  ordered = closed.sort_by { |row| row.to_s }
  ordered.map { |row| row - 1 }
end

def unrelated(value)
  return value if value.nil?

  value.to_s.strip
end

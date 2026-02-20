class_name MarkdownToBBCode
extends RefCounted

## Converts common Markdown to BBCode for RichTextLabel.


static func convert(md: String) -> String:
	var lines = md.split("\n")
	var result: Array[String] = []
	var in_code_block = false
	var code_block_lines: Array[String] = []
	var table_rows: Array[PackedStringArray] = []

	var i = 0
	while i < lines.size():
		var line = lines[i]
		var trimmed = line.strip_edges()

		# Code block toggle
		if trimmed.begins_with("```"):
			if in_code_block:
				in_code_block = false
				result.append("[indent][color=#B8D4E3]%s[/color][/indent]" % "\n".join(code_block_lines))
				code_block_lines.clear()
			else:
				in_code_block = true
			i += 1
			continue

		if in_code_block:
			code_block_lines.append(_escape_bbcode(line))
			i += 1
			continue

		# Table detection: line starts and ends with |
		if _is_table_row(trimmed):
			table_rows.clear()
			while i < lines.size():
				var tline = lines[i].strip_edges()
				if not _is_table_row(tline):
					break
				# Skip separator rows like |---|---|
				if not _is_table_separator(tline):
					table_rows.append(_parse_table_cells(tline))
				i += 1
			if not table_rows.is_empty():
				result.append(_build_table(table_rows))
			continue

		# Headings
		if trimmed.begins_with("#### "):
			result.append("[b]%s[/b]" % _inline(trimmed.substr(5)))
			i += 1
			continue
		if trimmed.begins_with("### "):
			result.append("[font_size=13][b]%s[/b][/font_size]" % _inline(trimmed.substr(4)))
			i += 1
			continue
		if trimmed.begins_with("## "):
			result.append("[font_size=14][b]%s[/b][/font_size]" % _inline(trimmed.substr(3)))
			i += 1
			continue
		if trimmed.begins_with("# "):
			result.append("[font_size=16][b]%s[/b][/font_size]" % _inline(trimmed.substr(2)))
			i += 1
			continue

		# Horizontal rule
		if trimmed == "---" or trimmed == "***" or trimmed == "___":
			result.append("[color=#555555]────────────────────[/color]")
			i += 1
			continue

		# Unordered list
		if trimmed.begins_with("- ") or trimmed.begins_with("* "):
			result.append("  • %s" % _inline(trimmed.substr(2)))
			i += 1
			continue

		# Ordered list
		var ordered = _match_ordered_list(trimmed)
		if ordered != "":
			result.append("  %s" % _inline(ordered))
			i += 1
			continue

		# Normal line
		result.append(_inline(line))
		i += 1

	# Unclosed code block
	if in_code_block and not code_block_lines.is_empty():
		result.append("[indent][color=#B8D4E3]%s[/color][/indent]" % "\n".join(code_block_lines))

	return "\n".join(result)


# ---- Table helpers ----

static func _is_table_row(line: String) -> bool:
	return line.begins_with("|") and line.ends_with("|") and line.length() > 1


static func _is_table_separator(line: String) -> bool:
	# Matches lines like |---|---|---| or | :---: | --- |
	var inner = line.substr(1, line.length() - 2)
	for cell in inner.split("|"):
		var stripped = cell.strip_edges()
		# Must be only dashes, colons, and spaces
		var clean = stripped.replace("-", "").replace(":", "").replace(" ", "")
		if clean != "" or stripped.is_empty():
			if clean != "":
				return false
	return true


static func _parse_table_cells(line: String) -> PackedStringArray:
	# Strip leading/trailing | and split by |
	var inner = line.substr(1, line.length() - 2)
	var parts = inner.split("|")
	var cells = PackedStringArray()
	for part in parts:
		cells.append(part.strip_edges())
	return cells


static func _build_table(rows: Array[PackedStringArray]) -> String:
	if rows.is_empty():
		return ""
	var col_count = 0
	for row in rows:
		col_count = maxi(col_count, row.size())

	var bb = "[table=%d]" % col_count
	for r in range(rows.size()):
		var row = rows[r]
		for c in range(col_count):
			var cell_text = row[c] if c < row.size() else ""
			if r == 0:
				# Header row - bold
				bb += "[cell][b]%s[/b][/cell]" % _inline(cell_text)
			else:
				bb += "[cell]%s[/cell]" % _inline(cell_text)
	bb += "[/table]"
	return bb


# ---- Inline formatting ----

static func _inline(text: String) -> String:
	# Strip markdown backslash escapes (e.g. \< \> \* \_ \` \| \\ )
	text = _strip_backslash_escapes(text)
	# Bold + italic ***text*** or ___text___
	text = _replace_pattern(text, "***", "***", "[b][i]", "[/i][/b]")
	text = _replace_pattern(text, "___", "___", "[b][i]", "[/i][/b]")
	# Bold **text** or __text__
	text = _replace_pattern(text, "**", "**", "[b]", "[/b]")
	text = _replace_pattern(text, "__", "__", "[b]", "[/b]")
	# Italic *text* or _text_
	text = _replace_pattern(text, "*", "*", "[i]", "[/i]")
	text = _replace_pattern(text, "_", "_", "[i]", "[/i]")
	# Inline code `text`
	text = _replace_pattern(text, "`", "`", "[color=#B8D4E3]", "[/color]")
	# Links [text](url)
	text = _replace_links(text)
	return text


static func _replace_pattern(text: String, open_delim: String, close_delim: String, bb_open: String, bb_close: String) -> String:
	var result = ""
	var idx = 0
	while idx < text.length():
		var open_pos = text.find(open_delim, idx)
		if open_pos == -1:
			result += text.substr(idx)
			break
		var content_start = open_pos + open_delim.length()
		var close_pos = text.find(close_delim, content_start)
		if close_pos == -1 or close_pos == content_start:
			result += text.substr(idx, open_pos - idx + open_delim.length())
			idx = content_start
			continue
		var content = text.substr(content_start, close_pos - content_start)
		if content.begins_with(" ") or content.ends_with(" "):
			result += text.substr(idx, open_pos - idx + open_delim.length())
			idx = content_start
			continue
		result += text.substr(idx, open_pos - idx)
		result += bb_open + content + bb_close
		idx = close_pos + close_delim.length()
	return result


static func _replace_links(text: String) -> String:
	var result = ""
	var idx = 0
	while idx < text.length():
		var bracket_pos = text.find("[", idx)
		if bracket_pos == -1:
			result += text.substr(idx)
			break
		var close_bracket = text.find("](", bracket_pos + 1)
		if close_bracket == -1:
			result += text.substr(idx, bracket_pos - idx + 1)
			idx = bracket_pos + 1
			continue
		var close_paren = text.find(")", close_bracket + 2)
		if close_paren == -1:
			result += text.substr(idx, bracket_pos - idx + 1)
			idx = bracket_pos + 1
			continue
		var link_text = text.substr(bracket_pos + 1, close_bracket - bracket_pos - 1)
		var url = text.substr(close_bracket + 2, close_paren - close_bracket - 2)
		result += text.substr(idx, bracket_pos - idx)
		result += "[url=%s][color=#6CA6CD]%s[/color][/url]" % [url, link_text]
		idx = close_paren + 1
	return result


static func _match_ordered_list(line: String) -> String:
	var dot_pos = line.find(". ")
	if dot_pos > 0 and dot_pos <= 3:
		var num_part = line.substr(0, dot_pos)
		if num_part.is_valid_int():
			return "%s. %s" % [num_part, line.substr(dot_pos + 2)]
	return ""


static func _escape_bbcode(text: String) -> String:
	text = text.replace("[", "[lb]")
	return text


static func _strip_backslash_escapes(text: String) -> String:
	var result = ""
	var idx = 0
	while idx < text.length():
		if text[idx] == "\\" and idx + 1 < text.length():
			# Skip the backslash, keep the next character
			idx += 1
			result += text[idx]
		else:
			result += text[idx]
		idx += 1
	return result

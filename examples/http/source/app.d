import sdpc;
import std.range, std.traits;
import std.stdio;

ParseResult!(R, ElementType!R, ParseError!R) t(R)(R i) if (isForwardRange!R) {
	alias RT = ParseResult!(R, ElementType!R, ParseError!R);
	if (i.empty)
		return RT(ParseError!R("eof", i));
	if (i.front > 127 || i.front < 32)
		return RT(ParseError!R("non ascii", i));
	return not_ch!"()<>@,:;\\\"/[]?={} "(i);
}

struct Request {
	dchar[] method;
	dchar[] uri;
	dchar[] ver;
}

struct Header {
	dchar[] name;
	dchar[][] values;
}

alias horiz_space = ch!" \t";
alias line_ending = transform_err!(choice!(token!"\r\n", token!"\n"), (x) => x[0]);
alias http_ver = transform!(seq!(token!"HTTP/", word!"0123456789."), (x) => x.v!1);
alias header_value = between!(many!horiz_space, many!(not_ch!"\r\n"), line_ending);

alias req_line = transform!(seq!(many!t, skip!whitespace,
                      many!(not_ch!" "), skip!whitespace,
                      http_ver,
                      line_ending), (x) => Request(x.v!0, x.v!2, x.v!4));// pragma(msg, typeof(x));});

alias header = transform!(seq!(many!t, token!":", many!header_value),
                          (x) => Header(x.v!0, x.v!2));

alias http = seq!(req_line, many!header, line_ending);

void main() {
	auto f = File("in.txt", "r");
	char[] buf = new char[f.size];
	f.rawRead(buf);

	auto r = many!http(cast(const(char)[])(buf));
	foreach(v; r.v) {
		writeln(v.v!0);
		writeln(v.v!1);
	}
}

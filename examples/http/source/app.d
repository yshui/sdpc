import sdpc;
import std.traits, std.stdio;
import std.functional : pipe;
import std.array : array;
import std.range : ElementType;

Result!(R, ElementType!R, Err!R) t(R)(R i) if (isForwardRange!R) {
	import std.algorithm, std.conv;
	alias RT = Result!(R, ElementType!R, Err!R);
	enum ex = "()<>@,:;\\\"/[]?={} ";
	string[] a = ex.map!(a => to!string([a])).array;
	if (i.empty)
		return RT(Err!R(a, true, i));
	if (i.front > 127 || i.front < 32)
		return RT(Err!R(a, true, i));
	return not_ch!ex(i);
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
alias line_ending = choice!(token!"\r\n", token!"\n");
alias http_ver = pipe!(seq!(token!"HTTP/", word!"0123456789."), wrap!"a.v!1");
alias header_value = pipe!(between!(many!horiz_space, many!(not_ch!"\r\n"), line_ending), wrap!array);
alias req_line =
pipe!(
      seq!(
           many!t, skip!whitespace,
           many!(not_ch!" "), skip!whitespace,
           http_ver,
           line_ending
      ),
      wrap!((ref x) => Request(array(x.v!0), array(x.v!2), array(x.v!4)))
);
alias header = pipe!(seq!(many!t, token!":", many!header_value),
                          wrap!((ref x) => Header(array(x.v!0), array(x.v!2))));
alias http = seq!(req_line, many!header, line_ending);

void main() {
	auto f = File("in.txt", "r");
	char[] buf = new char[f.size];
	f.rawRead(buf);

	enum runs = 1000;
	int sum = 0;
	foreach(i; 0..runs) {
		auto r = many!http(cast(const(char)[])(buf));
		auto v = r.v;
		sum+=v.length;
		if (i == 1)
			foreach(v2; r.v) {
				writeln(v2.v!0);
				writeln(v2.v!1);
			}
	}
	writeln(sum);
}

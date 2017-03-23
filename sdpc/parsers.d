/**
  Simple parsers

  Here are some commonly used parsers. Also as an example for how
  to use the combinators.

  Copyright: 2017 Yuxuan Shui
*/
module sdpc.parsers;
import sdpc.combinators,
       sdpc.primitives;
import std.traits,
       std.string,
       std.conv,
       std.range;
public @safe :

///Consumes nothing, always return OK
auto nop(R)(ref R i) if (isForwardRange!R) {
	return ParseResult!R(i);
}

struct ParseError(R) {
	dstring msg;
	R err_range;
}

/// Match a string, return the matched string
struct token(string t) {
	import std.algorithm.comparison;
	static auto opCall(R)(R i) if (isForwardRange!R && is(typeof(equal(i, t)))) {
		import std.array;
		alias RT = ParseResult!(R, string, ParseError!R);
		auto str = take(i, t.length);
		auto retr = i.save.drop(t.length);
		if (equal(str.save, t))
			return RT(retr, t);
		return RT(ParseError!R("expecting \""~t~"\", got \""~str.array.idup~"\"", retr));
	}
}

/// Match any character in accept
struct ch(alias accept) if (isSomeChar!(ElementType!(typeof(accept)))){
	static auto opCall(R)(R i) if (isForwardRange!R) {// && is(typeof(ElementType!R == accept[0]))) {
		alias RT = ParseResult!(R, ElementType!(typeof(accept)), ParseError!R);
		if (i.empty || accept.indexOf(i.front) == -1) {
			if (!i.empty)
				i.popFront;
			return RT(ParseError!R("expecting one of \""~accept~"\"", i));
		}

		auto ch = i.front;
		i.popFront;
		return RT(i, ch);
	}
}

/// Match any character except those in reject
struct not_ch(alias reject) if (isSomeChar!(ElementType!(typeof(reject)))){
	static auto opCall(R)(R i) if (isForwardRange!R) {
		alias RT = ParseResult!(R, ElementType!(typeof(reject)), ParseError!R);
		if (i.empty || reject.indexOf(i.front) != -1) {
			if (!i.empty)
				i.popFront;
			return RT(ParseError!R("not expecting one of \""~reject~"\"", i));
		}

		auto ch = i.front;
		i.popFront;
		return RT(i, ch);
	}
}

/// Parse a sequences of digits, return an array of number
alias digit(string _digits) = transform!(ch!_digits, (ch) => cast(int)_digits.indexOf(ch));

immutable string lower = "qwertyuiopasdfghjklzxcvbnm";
immutable string upper = "QWERTYUIOPASDFGHJKLZXCVBNM";
immutable string alphabet = lower ~ upper;
immutable string digits = "0123456789";

/**
  Parse a number
  Params:
	accept = digits allowed in the number, i-th character corresponds to digit i
	base = base
*/
template number(string accept = digits, int base = 10) if (accept.length == base) {
	import std.algorithm.iteration;
	alias number = transform!(many!(digit!accept), (x) => x.reduce!((a,b) => a*base+b));
}

///
unittest {
	auto i = "12354";
	auto rx = number!()(i);
	assert(rx.ok);
	assert(rx.v == 12354);

	i = "ffabc";
	auto rx1 = number!(digits~"abcdef", 16)(i);
	assert(rx1.ok);
	assert(rx1.v == 1047228);
}

/**
  Parse a sequence of characters
  Params:
	accept = an array of acceptable characters
*/
alias word(alias accept = alphabet) = transform!(many!(ch!accept), (x) => x.idup);

/// Parse an identifier, starts with a letter or _, followed by letter, _, or digits
auto identifier(R)(R i) if (isForwardRange!R) {
	auto ret = ch!(alphabet~"_")(i);
	alias RT = ParseResult!(R, ElementType!R[], ParseError!R);
	if (!ret.ok)
		return RT(ParseError!R("Failed to parse a identifier", i));
	auto ret2 = word!(alphabet~"_"~digits)(ret.cont);
	ElementType!R[] str = [ret.v];
	if (ret2.ok)
		str ~= ret2.v;
	return RT(ret2.cont, str);
}

///
unittest {
	auto i = "_asd1234a";
	auto rx2 = identifier(i);
	assert(rx2.ok);
	assert(!rx2.cont.length);
	assert(rx2.v == "_asd1234a");
}

/// Parse escaped character, \n, \r, \b, \" and \\
auto parse_escape1(R)(R i) if (isForwardRange!R) {
	alias RT = ParseResult!(R, dchar, ParseError!R);
	auto r = seq!(
		discard!(token!"\\"),
		transform_err!(choice!(
			token!"n",
			token!"b",
			token!"r",
			token!"\"",
			token!"\\"
		), (x) => x[0])
	)(i);
	if (!r.ok)
		return RT(ParseError!R("Failed to parse escape sequence", i));
	dchar res;
	final switch(r.v.v!1) {
	case "n":
		res = '\n';
		break;
	case "b":
		res = '\b';
		break;
	case "r":
		res = '\r';
		break;
	case "\"":
		res = '\"';
		break;
	case "\\":
		res = '\\';
		break;
	}
	return RT(r.cont, res);
}

/// Parse a string enclosed by a pair of quotes, and containing escape sequence
auto parse_string(R)(R i) if (isForwardRange!R) {
	alias RT = ParseResult!(R, dchar[], ParseError!R);
	auto r = between!(token!"\"",
		transform_err!(many!(choice!(
			parse_escape1,
			not_ch!"\""
		)), (x) => x[0]),
	token!"\"")(i);
	if (!r.ok)
		return RT(ParseError!R("Failed to parse a string", i));
	return r;
}

///
unittest {
	auto i = "\"asdf\\n\\b\"";
	auto r = parse_string(i);
	import std.format;
	assert(r.ok);
	assert(r.v == "asdf\n\b", format("%s", r.v));
}

/// Skip white spaces
alias skip_whitespace = skip!(choice!(token!" ", token!"\n", token!"\t"));

///
unittest {
	auto i = " \n\t    ";
	auto r = skip_whitespace(i);
	assert(r.ok);
	assert(!r.cont.length);
}

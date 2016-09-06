/**
  Simple parsers
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
struct not_ch(alias reject) if (isSomeChar!(ElementType!(typeof(accept)))){
	static auto opCall(R)(R i) if (isForwardRange!R) {
		alias RT = ParseResult!(R, Char, ParseError!R);
		if (i.empty || accept.indexOf(i.front) != -1) {
			if (!i.empty)
				i.popFront;
			return RT(ParseError!R("not expecting one of \""~accept~"\"", i));
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

/// Parse escaped character, \n, \r, \b, \" and \\
auto parse_escape1(R)(R i) if (isForwardRange!R) {
	alias RT = ParseResult!(R, char, ParseError!R);
	auto r = seq!(
		discard!(token!"\\"),
		choice!(
			token!"n",
			token!"b",
			token!"r",
			token!"\"",
			token!"\\"
		)
	)(i);
	if (!r.ok)
		return RT("Failed to parse escape sequence", i);
	char res;
	final switch(r.v) {
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
	alias RT = ParseResult!(R, string, ParseError!R);
	auto r = between!(token!"\"",
		many!(choice!(
			parse_escape1,
			not_ch!"\""
		)),
	token!"\"")(i);
	if (!r.ok)
		return RT(ParseError!R("Failed to parse a string", i));
	return r;
}

alias skip_whitespace = skip!(choice!(token!" ", token!"\n", token!"\t"));

///
unittest {
	import std.array;
	import std.stdio, std.format;

	string i = "(asdf)";
	auto r = between!(token!"(", token!"asdf", token!")")(i);
	assert(r.ok);
	assert(!r.r.length);

	i = "abcdaaddcc";
	alias abcdparser = many!(choice!(token!"a", token!"b", token!"c", token!"d"));
	auto r2 = abcdparser(i);
	assert(r2.ok);
	assert(!r2.r.length);

	i = "abcde";
	auto r3 = abcdparser(i);
	assert(r3.ok); //Parse is OK because 4 char are consumed
	assert(r3.r.length); //But the end-of-buffer is not reached

	auto r4 = seq!(token!"a", token!"b", token!"c", token!"d", token!"e")(i);
	assert(r4.ok);
	assert(r4.v.v!0 == "a");
	assert(r4.v.v!1 == "b");
	assert(r4.v.v!2 == "c");
	assert(r4.v.v!3 == "d");
	assert(r4.v.v!4 == "e");

	auto r5 = seq!(token!"a")(i); //test seq with single argument.
	assert(r5.ok);
	assert(r5.v.v!0 == "a");

	auto r6 = optional!(token!"x")(i);
	assert(r6.ok);
	assert(r6.v.isNull);

	i = "12354";
	auto rx = number!()(i);
	assert(rx.ok);
	assert(rx.v == 12354);

	i = "ffabc";
	auto rx1 = number!(digits~"abcdef", 16)(i);
	assert(rx1.ok);
	assert(rx1.v == 1047228);

	i = "_asd1234a";
	auto rx2 = identifier(i);
	assert(rx2.ok);
	assert(!rx2.r.length);
	assert(rx2.v == "_asd1234a");
}

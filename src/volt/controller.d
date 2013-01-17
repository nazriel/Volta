// Copyright © 2012, Jakob Bornecrantz.  All rights reserved.
// See copyright notice in src/volt/license.d (BOOST ver. 1.0).
module volt.controller;

import core.exception;
import std.algorithm : endsWith;
import std.path : dirSeparator, exists;
import std.process : system;
import std.stdio : stderr;

import volt.util.path;
import volt.exceptions;
import volt.interfaces;

import volt.parser.parser;
import volt.semantic.languagepass;
import volt.llvm.backend;

import volt.visitor.print;
import volt.visitor.debugprint;


/**
 * Default implementation of @link volt.interfaces.Controller Controller@endlink, replace
 * this if you wish to change the basic operation of the compiler.
 */
class VoltController : Controller
{
public:
	Settings settings;
	Frontend frontend;
	LanguagePass languagePass;
	Backend backend;

	Pass[] debugVisitors;

protected:
	string[] mSourceFiles;
	string[] mBitCodeFiles;
	ir.Module[string] mModules;

public:
	this(Settings s)
	{
		auto p = new Parser();
		p.dumpLex = false;

		auto lp = new VoltLanguagePass(s, this);

		auto b = new LlvmBackend(s.internalDebug);

		this(s, p, lp, b);

		// Setup default include paths.
		auto std = getExePath() ~ dirSeparator ~ "rt" ~ dirSeparator ~ "src";
		settings.includePaths = std ~ settings.includePaths;

		debugVisitors ~= new DebugPrintVisitor("Running DebugPrintVisitor:");
		debugVisitors ~= new PrintVisitor("Running PrintVisitor:");
	}

	/**
	 * Retrieve a Module by its name. Returns null if none is found.
	 */
	ir.Module getModule(ir.QualifiedName name)
	{
		auto p = name.toString() in mModules;
		ir.Module m;

		if (p !is null)
			m = *p;

		foreach (path; settings.includePaths) {
			if (m !is null)
				break;

			auto f = makeFilename(path, name.strings);

			if (!exists(f))
				continue;

			m = loadAndParse(f);
		}

		// Need to make sure that this module can
		// be used by other modules.
		if (m !is null) {
			languagePass.phase1(m);
		}

		return m;
	}

	void close()
	{
		frontend.close();
		languagePass.close();
		backend.close();

		settings = null;
		frontend = null;
		languagePass = null;
		backend = null;
	}

	void addFile(string file)
	{
		if (endsWith(file, ".d", ".v") > 0) {
			mSourceFiles ~= file;
		} else if (endsWith(file, ".bc")) {
			mBitCodeFiles ~= file;
		} else {
			auto str = format("unknown file type %s", file);
			throw new CompilerError(str);
		}
	}

	void addFiles(string[] files)
	{
		foreach(file; files)
			addFile(file);
	}

	int compile()
	{
		int ret;
		if (settings.noCatch) {
			ret = intCompile();
		} else try {
			ret = intCompile();
		} catch (CompilerPanic e) {
			stderr.writefln(e.msg);
			if (e.file !is null)
				stderr.writefln("%s:%s", e.file, e.line);
			return 2;
		} catch (CompilerError e) {
			stderr.writefln(e.msg);
			return 1;
		} catch (Exception e) {
			stderr.writefln("panic: %s", e.msg);
			if (e.file !is null)
				stderr.writefln("%s:%s", e.file, e.line);
			return 2;
		} catch (Error e) {
			stderr.writefln("panic: %s", e.msg);
			if (e.file !is null)
				stderr.writefln("%s:%s", e.file, e.line);
			return 2;
		}

		return ret;
	}

protected:
	/**
	 * Loads a file and parses it, also adds it to the loaded modules.
	 */
	ir.Module loadAndParse(string file)
	{
		Location loc;
		loc.filename = file;

		auto src = cast(string) read(loc.filename);
		auto m = frontend.parseNewFile(src, loc);
		mModules[m.name.toString()] = m;

		return m;
	}

	int intCompile()
	{
		ir.Module[] mods;

		// Load all modules to be compiled.
		// Don't run phase 1 on them yet.
		foreach (file; mSourceFiles) {
			mods ~= loadAndParse(file);
		}

		// Force phase 1 to be executed on the modules.
		foreach (mod; mods)
			languagePass.phase1(mod);

		ir.Module[] dmdIsStupid;
		foreach (mod; mModules)
			dmdIsStupid ~= mod;

		// All modules need to be run trough phase2.
		languagePass.phase2(dmdIsStupid);

		// All modules need to be run trough phase3.
		languagePass.phase3(dmdIsStupid);

		if (settings.internalDebug) {
			foreach(pass; debugVisitors) {
				foreach(mod; mods) {
					pass.transform(mod);
				}
			}
		}

		if (settings.noBackend)
			return 0;

		// We will be modifing this later on,
		// but we don't want to change mBitCodeFiles.
		string[] bitCodeFiles = mBitCodeFiles;

		foreach (mod; mods) {
			string o = temporaryFilename(".bc");
			backend.setTarget(o, TargetType.LlvmBitcode);
			backend.compile(mod);
			bitCodeFiles ~= o;
		}

		string linkInputFiles;
		string of = settings.outputFile is null ? DEFAULT_EXE : settings.outputFile;
		string cmd;
		int ret;

		foreach (file; bitCodeFiles) {
			linkInputFiles ~= " \"" ~ file ~ "\" ";
		}

		if (settings.emitBitCode) {
			cmd = format("llvm-link -o \"%s\" %s", of, linkInputFiles);
			ret = system(cmd);
			if (ret)
				return ret;
		} else if (settings.noLink) {
			string link = temporaryFilename(".bc");
			cmd = format("llvm-link -o \"%s\" %s", link, linkInputFiles);
			ret = system(cmd);
			if (ret)
				return ret;

			string as = temporaryFilename(".as");
			cmd = format("llc -o \"%s\" \"%s\"", as, link);
			version (darwin)
				cmd ~= " -disable-cfi";
			ret = system(cmd);
			if (ret)
				return ret;

			cmd = format("llvm-mc -filetype=obj -o \"%s\" \"%s\"", of, as);
			ret = system(cmd);
			if (ret)
				return ret;
		} else {
			// this is just during bring up.
			linkInputFiles ~= " \"" ~ getExePath() ~ dirSeparator ~ "rt/rt.bc\"";

			cmd = format("llvm-ld -native -o \"%s\" %s", of, linkInputFiles);
			ret = system(cmd);
			if (ret)
				return ret;
		}

		return 0;
	}

	this(Settings s, Frontend f, LanguagePass lp, Backend b)
	{
		this.settings = s;
		this.frontend = f;
		this.languagePass = lp;
		this.backend = b;
	}
}

version (Windows) {
	enum DEFAULT_EXE = "a.exe";
} else {
	enum DEFAULT_EXE = "a.out";
}

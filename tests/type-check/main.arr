#lang pyret

import ast as A
import either as E
import filelib as FL
import namespace-lib as N
import runtime-lib as R
import load-lib as L
import string-dict as SD
import file("../../src/arr/compiler/compile-lib.arr") as CL
import file("../../src/arr/compiler/compile-structs.arr") as CS
import file("../../src/arr/compiler/type-defaults.arr") as TD
import file("../../src/arr/compiler/locators/builtin.arr") as BL
import file("../../src/arr/compiler/cli-module-loader.arr") as CLI

fun string-to-locator(name, str :: String):
  {
    needs-compile(self, provs): true end,
    get-modified-time(self): 0 end,
    get-options(self, options): options end,
    get-module(self): CL.pyret-string(str) end,
    get-extra-imports(self): CS.minimal-imports end,
    get-native-modules(self): [list:] end,
    get-dependencies(self): CL.get-dependencies(self.get-module(), self.uri()) end,
    get-globals(self): CS.standard-globals end,
    get-namespace(self, runtime): N.make-base-namespace(runtime) end,
    uri(self): "tc-test://" + name end,
    name(self): name end,
    set-compiled(self, ctxt, provs): nothing end,
    get-compiled(self): none end,
    _equals(self, that, rec-eq): rec-eq(self.uri(), that.uri()) end
  }
end

fun dfind(ctxt, dep):
  l = cases(CS.Dependency) dep:
    | builtin(modname) =>
      BL.make-builtin-locator(modname)
  end
  CL.located(l, nothing)
end

compile-str = lam(filename, str):
  l = string-to-locator(filename, str)
  wlist = CL.compile-worklist(dfind, l, {})
  result = CL.compile-program(wlist, CS.default-compile-options.{type-check: true})
  errors = result.loadables.filter(CL.is-error-compilation)
  cases(List) errors:
    | empty =>
      E.right(result.loadables)
    | link(_, _) =>
      E.left(errors.map(_.result-printer))
  end
end

var realm = L.empty-realm()
r = R.make-runtime()

fun compile-program(path):
  base-module = CS.dependency("file", [list: path])
  base = CLI.module-finder({current-load-path:"./", cache-base-dir: "./compiled"}, base-module)
  result = CL.compile-and-run-locator(
    base.locator,
    CLI.module-finder,
    base.context,
    realm,
    r,
    [SD.mutable-string-dict:],
    CS.default-compile-options.{type-check: true})
  cases(E.Either) result block:
    | left(err) => result
    | right(answer) =>
      realm := L.get-result-realm(answer)
      result
  end
end

fun is-arr-file(filename):
  string-index-of(filename, ".arr") == (string-length(filename) - 4)
end

check "These should all be good programs":
  base = "./tests/type-check/good/"
  good-progs = FL.list-files(base)
  for each(prog from good-progs):
    when is-arr-file(prog) block:
      #print("Running test for: " + prog + "\n")
      filename = base + prog
      result = compile-program(filename)
      result satisfies E.is-right
      when E.is-left(result):
        "Should be okay: " is filename
      end
    end
  end
end

#|
check "These should all be bad programs":
  base = "./tests/type-check/bad/"
  bad-progs = FL.list-files(base)
  for each(prog from bad-progs):
    when is-arr-file(prog) block:
      filename  = base + prog
      result = compile-program(filename)
      result satisfies E.is-left
      cases(E.Either) result:
        | right(_) =>
          "Should be error: " is filename
        | left(problems) =>
          for each(problem from problems):
            tostring(problem) satisfies is-string
          end
      end
    end
  end
end
|#

#|
check "All builtins should have a type":
  covered = TD.make-default-types()
  for each(builtin from CS.standard-globals.values.keys-list()):
    builtin-typ = covered.get-now(A.s-global(builtin).key())
    builtin-typ satisfies is-some
    when is-none(builtin-typ):
      "Should have a type: " is builtin
    end
  end
end
|#

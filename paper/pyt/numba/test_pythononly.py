from listings_noslice import *
import sys
import time

Examples_san = {"nx" : [3, 3, 3], 
                "ny" : [3, 3, 3],
                "Cx" : [0, 1, 1],
                "Cy" : [1, 0, 0],
                "nt" : [3, 4, 4],
                "it" : [1, 1, 3]}

Examples_time = {"nx" : [64, 81, 512],
                 "ny" : [64, 81, 512],
                 "Cx" : [.2, .2, .2],
                 "Cy" : [.5, .5, .5],
                 "nt" : [4096, 2557, 64],
                 "it" : [3, 3, 3]}

# reading array from input/output files 
def read_file(fname, nx, ny):
  tmp = numpy.empty((nx, ny), real_t)
  with open(fname, 'r') as f:
    x = 0
    for line in f:
      tmp[x,:] = numpy.fromstring(line, dtype=real_t, sep='\t')
      x += 1
  assert(x == nx)
  return tmp

# comapring array from output files with results after advection
# dec is the accuracy of comparison, it might be needed sometimes to use smaller
def checking_output(fin, fout, nx, ny, Cx, Cy, nt, it, dec=4):
  slv = Mpdata(it, Cyclic, Cyclic, nx, ny)
  slv.state()[:] = read_file(fin, nx, ny)
  slv.courant(0)[:] = Cx
  slv.courant(1)[:] = Cy
  t0 = time.time()
  slv.solve(nt)
  print "time", time.time() - t0

  diff = numpy.amax(abs(slv.state() - read_file(fout, nx, ny)))
  print "diff=", diff
  if nx*ny < 100:
    print "out", slv.state()
  if (diff >= .5 * pow(10, -dec)): 
    print slv.state().dtype, slv.state()
    tmp = read_file(fout, nx, ny)
    print tmp.dtype, tmp
    print numpy.max(numpy.abs(slv.state() - tmp))
    raise Exception()

def main(ex = Examples_san, kat="/glade/u/home/jarecka/mpdata/paper/tests/sanity/"):
  print "sys", sys.argv
# progarm should work when running without any additional command-line arguments 
# or with one additional command-line argument "sanity" or "timing"
  if len(sys.argv) == 1:
    pass
  elif len(sys.argv) == 2:
    if sys.argv[1] == "sanity":
      ex, kat = Examples_san, "/glade/u/home/jarecka/mpdata/paper/tests/sanity/"
    elif sys.argv[1] == "timing":
      ex, kat = Examples_time, "/glade/u/home/jarecka/mpdata/paper/tests/timing/"
    else:
      raise Exception('expecting sanity or timing as the second argument') 
  else:
    raise Exception('too many arguments!')

  for i in range(len(ex["nx"])):
    filename = kat
    arg_func = []
    #creating neames of input/output files, some arguments needs additional operation 
    for arg in ["nx", "ny", "Cx", "Cy", "nt", "it"]:
      if arg in ["nx", "ny"] and len(str(ex[arg][i])) < 4:
        arg_val = "0"
        for i in range(3 - len(str(ex[arg][i]))):
          arg_val += "0"
        arg_val += str(ex[arg][i])
      elif "." in str(ex[arg][i]):
        arg_val = str(ex[arg][i])[1:]
      else:
        arg_val = str(ex[arg][i])
      filename = filename + str(arg) + "=" + arg_val + "_"
      arg_func.append(ex[arg][i])
    fin = filename[:-1] + ":in"
    fout = filename[:-1] + ":out"
    print "arg fun", arg_func

    checking_output(fin, fout, *arg_func)

if __name__ == "__main__":
    main()

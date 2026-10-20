using System;
using System.IO;
using System.Linq;
using System.Reflection;
using System.Runtime.Loader;
using System.Security.Cryptography;
public class ImportAnimation {
 public static int Main(string[] args) {
  if(args.Length!=4)throw new Exception("Expected pinned WolvenKit folder, game executable, source GLB, target anims");
  var wk=Path.GetFullPath(args[0]);
  var cliHash=Convert.ToHexString(SHA256.HashData(File.ReadAllBytes(Path.Combine(wk,"WolvenKit.CLI.exe")))).ToLowerInvariant();
  if(cliHash!="7ae9c308da2fe003220b55ce4ca9c122b51f0701a67db1618cca3ff4f7ff6738")throw new Exception("Pinned WolvenKit9.0.1 required");
  AssemblyLoadContext.Default.Resolving+=(context,name)=>{var path=Path.Combine(wk,name.Name+".dll");return File.Exists(path)?context.LoadFromAssemblyPath(path):null;};
  Directory.SetCurrentDirectory(wk);
  var cli=Assembly.LoadFrom(Path.Combine(wk,"WolvenKit.CLI.dll"));
  var core=Assembly.LoadFrom(Path.Combine(wk,"WolvenKit.Core.dll"));
  var oodle=core.GetType("WolvenKit.Core.Compression.Oodle")??throw new Exception("Oodle type missing");
  var load=oodle.GetMethods().Single(m=>m.Name=="Load");
  if(!(bool)load.Invoke(null,load.GetParameters().Select(p=>p.DefaultValue).ToArray()))throw new Exception("Oodle initialization failed");
  Console.WriteLine("Oodle ready");
  var setData=typeof(AppContext).GetMethod("SetData",BindingFlags.Public|BindingFlags.Static)??throw new Exception("Required runtime AppContext.SetData is unavailable");
  setData.Invoke(null,new object[]{"APP_CONTEXT_BASE_DIRECTORY",wk+Path.DirectorySeparatorChar});
  var genericHost=cli.GetType("WolvenKit.CLI.GenericHost")??throw new Exception("GenericHost missing");
  var builder=genericHost.GetMethod("CreateHostBuilder",BindingFlags.Public|BindingFlags.Static).Invoke(null,new object[]{Array.Empty<string>()});
  var host=builder.GetType().GetMethod("Build").Invoke(builder,null);
  Console.WriteLine("Host ready");
  var provider=(IServiceProvider)host.GetType().GetProperty("Services").GetValue(host);
  var common=Assembly.LoadFrom(Path.Combine(wk,"WolvenKit.Common.dll"));
  var manager=provider.GetService(common.GetType("WolvenKit.Common.IArchiveManager"))??throw new Exception("ArchiveManager missing");
  manager.GetType().GetMethod("LoadGameArchives").Invoke(manager,new object[]{new FileInfo(args[1])});
  var tools=provider.GetService(common.GetType("WolvenKit.Common.Interfaces.IModTools"));
  var importArgs=Activator.CreateInstance(common.GetType("WolvenKit.Common.Model.Arguments.GltfImportArgs"));
  importArgs.GetType().GetProperty("ForceCompressedEncoding").SetValue(importArgs,true);
  using(var stream=new FileStream(args[3],FileMode.Open,FileAccess.ReadWrite)) {
   var success=(bool)tools.GetType().GetMethod("ImportAnims").Invoke(tools,new object[]{new FileInfo(args[2]),stream,importArgs});
   Console.WriteLine("ANIMATION_IMPORT_RESULT="+success);return success?0:1;
  }
 }
}

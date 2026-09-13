require 'open3'
require 'json'
abort 'Usage: prepare-starrail-trial.rb wine prefix' unless ARGV.length == 2
wine,prefix=ARGV
abort 'Only the isolated Mac window trial prefix is allowed' unless prefix.end_with?('/native-window-adapter/starrail-prefix')
env={'WINEPREFIX'=>prefix,'WINEDEBUG'=>'-all','WINEMSYNC'=>'1'}
key='HKCU\\Software\\miHoYo\\崩坏：星穹铁道'
run=proc do |*args|
  output,status=Open3.capture2e(env,wine,*args)
  abort "Failed: #{args[0,2].join(' ')}" unless status.success?
  output
end
run.call('reg','add','HKCU\\Software\\Wine\\Mac Driver','/v','RetinaMode','/t','REG_SZ','/d','y','/f')
# User confirmed a physical 4K panel. Do not infer this limit from a 5K backing buffer.
resolution={width:3840,height:2160,isFullScreen:false}.to_json+"\0"
run.call('reg','add',key,'/v','GraphicsSettings_PCResolution_h431323223','/t','REG_BINARY','/d',resolution.unpack1('H*'),'/f')
{'Screenmanager Resolution Width_h182942802'=>3840,
 'Screenmanager Resolution Height_h2627697771'=>2160,
 'Screenmanager Fullscreen mode_h3630240806'=>3}.each do |name,value|
  run.call('reg','add',key,'/v',name,'/t','REG_DWORD','/d',value.to_s,'/f')
end
output=run.call('reg','query',key)
output.lines.each do |line|
  name=line.strip.split(/\s+/).first
  next unless name && (name=='MIHOYOSDK_WEBVIEW_RENDER_METHOD_h1573598267' || name.start_with?('HOYO_WEBVIEW_RENDER_METHOD_ABTEST_'))
  run.call('reg','delete',key,'/v',name,'/f')
end
puts 'Isolated trial prepared: Retina enabled, 3840x2160 windowed, webview render cache reset.'

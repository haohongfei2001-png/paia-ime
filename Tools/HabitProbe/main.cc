// Authored finite spelling-policy control using the same pinned native helpers.
// Never linked into the application; no synthetic Chinese candidates are installed.
#include "../G01Bridge/paia_g01.cc"
#include <iostream>
#include <vector>

namespace habit_probe {
void require(bool value,const char* message){if(!value)throw std::runtime_error(message);}
size_t commits=0,negatives=0,diagnostics=0;
struct Observed {bool found=false,complete=false;Code code;std::string type;};
Observed inspect(const std::string& schema,const std::string& raw,const std::string& text,bool commit) {
  OwnedSession owned;create(owned,schema,{},"");auto ctx=session(owned.id)->context();std::string prefix;
  for(unsigned char key:raw){prefix+=static_cast<char>(key);require(api->process_key(owned.id,key,0),"ordinary spelling key was not handled");require(ctx->input()==prefix,"engine did not retain exact typed source");}
  require(ctx->caret_pos()==raw.size(),"spelling caret mismatch");
  RimeCommit unexpected{};RIME_STRUCT_INIT(RimeCommit,unexpected);bool early=api->get_commit(owned.id,&unexpected);
  if(early){api->free_commit(&unexpected);}require(!early,"spelling committed before selection");
  Observed result;size_t index=0,selectedIndex=0;
  for(;index<2048;++index){
    auto c=candidate(ctx,index);if(!c){result.complete=true;break;}
    if(!result.found && c->start()==0 && c->end()==raw.size() && c->text()==text && !candidate_code(c).empty()){
      result.found=true;result.code=candidate_code(c);result.type=c->type();selectedIndex=index;
    }
  }
  if(result.found && commit){
    require(ctx->Select(selectedIndex),"actual candidate selection failed");
    const auto spans=selected(ctx);require(spans.size()==1 && spans[0].start==0 && spans[0].end==raw.size() && spans[0].text==text && same_code(spans[0].code,result.code),"selected canonical span changed");
    require(api->commit_composition(owned.id),"native commit failed");
    RimeCommit value{};RIME_STRUCT_INIT(RimeCommit,value);const bool got=api->get_commit(owned.id,&value);
    const std::string actual=got && value.text?value.text:"";if(got)api->free_commit(&value);
    require(got && actual==text,"native drained text mismatch");
    RimeCommit again{};RIME_STRUCT_INIT(RimeCommit,again);const bool duplicate=api->get_commit(owned.id,&again);if(duplicate)api->free_commit(&again);
    require(!duplicate,"second native commit exists");++commits;
  }
  std::cout<<"HABIT_NATIVE_CASE schema="<<schema<<" raw="<<raw<<" target="<<text<<" found="<<result.found<<" complete="<<result.complete<<" type="<<result.type<<" code=";
  for(auto syllable:result.code){std::cout<<syllable<<',';}std::cout<<'\n';
  return result;
}
Code accepted(const std::string& schema,const std::string& raw,const std::string& text){auto x=inspect(schema,raw,text,true);require(x.found,"declared spelling target not found");return x.code;}
void contrast(const std::string& schema,const std::string& normal,const std::string& changed,const std::string& text,bool enabled){
  const auto expected=accepted(schema,normal,text);const auto actual=inspect(schema,changed,text,enabled);
  if(enabled)require(actual.found && same_code(actual.code,expected),"policy changed canonical syllable identity");
  else{require(actual.complete && !actual.found,"disabled policy target present or search incomplete");++negatives;}
}
void run(const std::string& schema,const std::string& kind,bool traditional,bool fuzzy,bool correction){
  const bool full=kind=="full";
  for(const auto& item:std::vector<std::pair<std::string,std::string>>{{"nv","女"},{"lv",traditional?"綠":"绿"},{full?"lve":"lt","略"},{full?"nve":"nt","虐"},{"xi'an","西安"},{full?"xian":"xm","先"},{full?"shurufa":"uurufa",traditional?"輸入法":"输入法"}})accepted(schema,item.first,item.second);
  if(full){accepted(schema,"lue","略");accepted(schema,"nue","虐");}
  else{
    accepted(schema,"xi'aj","西安");
    const bool flypy=kind=="flypy";
    for(const auto& item:std::vector<std::pair<std::string,std::string>>{{"aa","啊"},{"ee",traditional?"額":"额"},{"oo","哦"},{"an","安"},{"aj","安"},{"en","恩"},{"ef","恩"},{"ah","昂"},{"eg","鞥"},{"er","而"},{flypy?"ad":"al",traditional?"愛":"爱"},{flypy?"ac":"ak",traditional?"奧":"奥"},{flypy?"ew":"ez",traditional?"誒":"诶"},{flypy?"oz":"ob",traditional?"歐":"欧"}})accepted(schema,item.first,item.second);
    // A prefix-completion candidate is not proof of a complete one-key encoding.
    for(const auto& item:std::vector<std::pair<std::string,std::string>>{{"a","啊"},{"e",traditional?"額":"额"},{"o","哦"}}){inspect(schema,item.first,item.second,false);++diagnostics;}
  }
  contrast(schema,full?"zhongguo":"vsgo",full?"zongguo":"zsgo",traditional?"中國":"中国",fuzzy);
  contrast(schema,full?"zonggong":"zsgs",full?"zhonggong":"vsgs",traditional?"總攻":"总攻",fuzzy);
  contrast(schema,full?"shurufa":"uurufa","surufa",traditional?"輸入法":"输入法",fuzzy);
  contrast(schema,full?"suyu":"suyu",full?"shuyu":"uuyu",traditional?"俗語":"俗语",fuzzy);
  contrast(schema,full?"lantian":"ljtm",full?"nantian":"njtm",traditional?"藍天":"蓝天",fuzzy);
  contrast(schema,full?"nongtian":"nstm",full?"longtian":"lstm",traditional?"農田":"农田",fuzzy);
  contrast(schema,full?"chumen":"iumf",full?"cumen":"cumf",traditional?"出門":"出门",fuzzy);
  contrast(schema,full?"culve":"cult",full?"chulve":"iult","粗略",fuzzy);
  if(full){contrast(schema,"zhi","hzi","知",correction);contrast(schema,"zhongguo","hzongguo",traditional?"中國":"中国",correction);}
}
}
int main(int argc,char** argv){
  using namespace habit_probe;if(argc!=3){std::cerr<<"usage: habit-probe authored-shared fresh-user\n";return 2;}bool initialized=false;
  try{
    api=rime_get_api();require(api && std::strcmp(api->get_version(),"1.16.0")==0,"wrong pinned engine");
    RimeTraits traits{};RIME_STRUCT_INIT(RimeTraits,traits);traits.shared_data_dir=argv[1];traits.user_data_dir=argv[2];traits.distribution_name="PAIA authored spelling contract";traits.distribution_code_name="paia_habits";traits.distribution_version="0";traits.app_name="rime.paia_habits";traits.min_log_level=3;traits.log_dir="";
    api->setup(&traits);api->initialize(&traits);initialized=true;api->deployer_initialize(&traits);size_t schemas=0;
    for(const std::string kind:{"full","flypy","natural"})for(bool traditional:{false,true})for(bool punctuation:{false,true})for(bool fuzzy:{false,true})for(bool correction:{true,false}){
      if(kind!="full" && !correction)continue;
      const std::string schema="paia_habit_"+kind+(traditional?"_traditional":"")+(punctuation?"_punct":"_ascii")+(fuzzy?"_fuzzy":"")+(kind=="full" && !correction?"_strict":"");
      require(api->deploy_schema((std::string(argv[1])+"/"+schema+".schema.yaml").c_str()),"authored policy schema deployment failed");
      run(schema,kind,traditional,fuzzy,correction);++schemas;
    }
    require(schemas==32 && commits==928 && negatives==144 && diagnostics==48,"native policy matrix coverage changed");
    mixed::close_all();api->finalize();initialized=false;
    std::cout<<"HABIT_NATIVE_TOTAL schemas="<<schemas<<" commits="<<commits<<" exhaustive_negatives="<<negatives<<" single_key_diagnostics="<<diagnostics<<" ENGINE_NATIVE finite authored data; no language-quality claim\n";return 0;
  }catch(const Failure& f){std::cerr<<"HABIT_NATIVE_FAILED code="<<f.code<<'\n';}catch(const std::exception& e){std::cerr<<"HABIT_NATIVE_FAILED "<<e.what()<<'\n';}
  if(initialized){mixed::close_all();api->finalize();}return 1;
}

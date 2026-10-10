// Engine-only feasibility experiment, not linked into the app or Swift bridge.
// Reuse the exact pinned G01 replay helpers. Production G01 contracts stay unchanged.
#include "../G01Bridge/paia_g01.cc"
#include <rime/translation.h>
#include <chrono>
#include <iostream>
#include <sstream>

namespace mixed_probe {
struct CheckFailure : std::runtime_error { using std::runtime_error::runtime_error; };
void require(bool value, const char* message) { if (!value) throw CheckFailure(message); }
struct Part {
  enum Kind { chinese, literal, unconfirmed } kind;
  std::string raw, text;
  Code code;
};
// Only literal identity transport is synthesized. This distinct type never represents
// a Chinese decoding result, and is not exposed as an ordinary language candidate.
class LiteralIdentity final : public SimpleCandidate {
 public:
  LiteralIdentity(size_t start, size_t end, const std::string& text)
      : SimpleCandidate("paia_explicit_literal_probe", start, end, text) {}
};
std::string witness(uint64_t id) {
  auto s=session(id);auto ctx=s->context();std::ostringstream out;
  char schema[256]={};require(api->get_current_schema(id,schema,sizeof(schema)),"witness schema unavailable");out<<schema<<'\n';
  for(const auto& option:ctx->options())out<<option.first<<':'<<option.second<<'\n';
  out<<ctx->input()<<'\n'<<ctx->caret_pos()<<'\n'<<ctx->GetCommitText()<<'\n'<<s->commit_text()<<'\n';
  for(const auto& seg:ctx->composition()) {
    out<<seg.start<<':'<<seg.end<<':'<<seg.length<<':'<<seg.status<<':'<<seg.selected_index<<'\n';
    for(const auto& tag:seg.tags)out<<tag<<',';out<<'\n';
    if(auto c=seg.GetSelectedCandidate()){
      out<<c->type()<<':'<<c->text()<<'\n';for(auto syllable:candidate_code(c))out<<syllable<<',';out<<'\n';
    }
  }
  return out.str();
}
std::vector<Part> observed_prefix(uint64_t id) {
  auto ctx=session(id)->context();std::vector<Part> result;size_t end=0;
  for(const auto& seg:ctx->composition()) {
    if(seg.start==seg.end || seg.status<Segment::kSelected)break;
    auto c=seg.GetSelectedCandidate();
    require(c && c->start()==end && c->end()<=ctx->input().size(),"noncontiguous Chinese witness");
    require(c->type()!="paia_explicit_literal_probe" && !candidate_code(c).empty(),"source must be a genuine phonetic Chinese candidate");
    result.push_back({Part::chinese,ctx->input().substr(end,c->end()-end),c->text(),candidate_code(c)});end=c->end();
  }
  if(end<ctx->input().size())result.push_back({Part::unconfirmed,ctx->input().substr(end),"",{}});
  return result;
}
void insert_identity(Context* ctx,size_t start,const std::string& literal) {
  require(!literal.empty(),"empty literal is an edit, not an identity segment");
  auto comp=ctx->composition();
  while(!comp.empty() && comp.back().start>=start)comp.pop_back();
  require((comp.empty()?0:comp.back().end)==start,"literal crosses existing anchor");
  for(const auto& seg:comp)require(seg.status>=Segment::kSelected,"literal implicitly confirms preceding raw");
  comp.Reset(ctx->input());
  Segment seg(static_cast<int>(start),static_cast<int>(start+literal.size()));
  seg.status=Segment::kSelected;seg.tags.insert("paia_explicit_literal_probe");
  auto translation=New<FifoTranslation>();translation->Append(New<LiteralIdentity>(start,start+literal.size(),literal));
  seg.menu=New<Menu>();seg.menu->AddTranslation(translation);seg.selected_index=0;
  comp.push_back(std::move(seg));comp.Forward();ctx->set_composition(std::move(comp));
  // Leave native caret at full input. A future logical caret is separate.
  ctx->set_caret_pos(ctx->input().size());
}
void verify_layout(Context* ctx,const std::vector<Part>& parts) {
  std::string raw;for(const auto& part:parts)raw+=part.raw;
  require(ctx->input()==raw && ctx->composition().input()==raw,"raw or composition suffix lost");
  require(ctx->caret_pos()==raw.size(),"native caret must remain at full input");
  size_t start=0;
  for(const auto& part:parts) {
    if(part.kind==Part::unconfirmed) {
      require(start+part.raw.size()==raw.size(),"initial probe permits one trailing raw span only");
      require(frontier(ctx)==start,"raw suffix has silently been selected");
      require(candidate(ctx,0)!=nullptr,"unconfirmed suffix has no real candidates");
    } else {
      bool found=false;
      for(const auto& seg:ctx->composition())if(seg.start==start && seg.status>=Segment::kSelected) {
        auto c=seg.GetSelectedCandidate();
        require(c && c->end()==start+part.raw.size() && c->text()==part.text,"selected anchor changed");
        if(part.kind==Part::literal)require(c->type()=="paia_explicit_literal_probe" && c->text()==part.raw,"literal provenance mismatch");
        else require(c->type()!="paia_explicit_literal_probe" && !part.code.empty() && same_code(candidate_code(c),part.code),"Chinese provenance/code changed");
        found=true;break;
      }
      require(found,"selected anchor missing");
    }
    start+=part.raw.size();
  }
}
void replay(uint64_t source,const std::vector<Part>& parts,size_t work,OwnedSession& trial) {
  std::string raw;bool suffix=false;
  for(const auto& part:parts) {
    require(!suffix,"raw suffix must be last in this bounded probe");
    require(!part.raw.empty() && part.raw.find('\0')==std::string::npos,"invalid raw");
    if(part.kind==Part::literal)require(part.text==part.raw,"literal text must be exact input");
    suffix=part.kind==Part::unconfirmed;raw+=part.raw;
  }
  require(raw.size()<=4096 && parts.size()<=256,"probe limits");
  char schema[256]={};require(api->get_current_schema(source,schema,sizeof(schema)),"source schema unavailable");
  create(trial,schema,session(source)->context()->options(),raw);auto ctx=session(trial.id)->context();
  size_t offset=0;Budget budget{work};
  for(const auto& part:parts) {
    if(part.kind==Part::chinese) {
      require(choose(ctx,{offset,offset+part.raw.size(),0,part.text,part.code},budget),"actual Chinese replay failed");
    } else if(part.kind==Part::literal) {
      budget.spend();insert_identity(ctx,offset,part.raw);
    }
    offset+=part.raw.size();
  }
  verify_layout(ctx,parts);require(session(trial.id)->commit_text().empty(),"unsolicited commit during replay");
}
void drain_exact(uint64_t id,const std::string& expected) {
  require(session(id)->commit_text().empty(),"commit already pending");
  require(api->commit_composition(id),"explicit native commit refused");
  RIME_STRUCT(RimeCommit,c);require(api->get_commit(id,&c),"native commit missing");
  const std::string actual=c.text?c.text:"";api->free_commit(&c);
  require(actual==expected,"final native commit differs (preedit alone is insufficient)");
  RIME_STRUCT(RimeCommit,again);const bool duplicate=api->get_commit(id,&again);if(duplicate)api->free_commit(&again);
  require(!duplicate,"second native commit read not empty");
}
Span choose_prefix(Context* ctx,size_t end,const std::string& wanted,bool alternate=false) {
  an<Candidate> chosen;size_t index=0;
  for(;index<2048;++index) {
    auto c=candidate(ctx,index);if(!c)break;
    if(c->start()!=frontier(ctx) || c->end()!=end || candidate_code(c).empty())continue;
    if((alternate && index>0 && c->text()!=wanted) || (!alternate && c->text()==wanted)){chosen=c;break;}
  }
  require(chosen!=nullptr,"test Chinese choice unavailable");
  Span result(chosen->start(),chosen->end(),index,chosen->text(),candidate_code(chosen));
  require(ctx->Select(index) && confirmed(ctx,result),"real selection failed");return result;
}
int run(const std::string& schema,const std::string& raw,size_t split,bool alternate) {
  OwnedSession source;create(source,schema,{},raw);auto original=session(source.id)->context();
  const auto first=choose_prefix(original,split,"你好",alternate);choose_prefix(original,raw.size(),"世界");
  const auto before=witness(source.id);const auto anchors=observed_prefix(source.id);
  require(anchors.size()==2 && anchors[0].kind==Part::chinese && anchors[1].kind==Part::chinese,"fixture requires two genuine anchors");
  const std::vector<std::string> literals={"RAG","data","user_id","https://example.test/a_b?q=1.2","/tmp/A-b.txt","v1.2.3","3.14","12:30","x != \"a\"","，","ｑ","𠀀","é","👩🏽‍💻"};
  int passed=0;
  for(const auto& value:literals)for(size_t where=0;where<=2;++where) {
    auto parts=anchors;parts.insert(parts.begin()+where,{Part::literal,value,value,{}});
    OwnedSession trial;replay(source.id,parts,2048,trial);
    // A normal full-input recompose must not lose this explicit literal anchor.
    session(trial.id)->context()->update_notifier()(session(trial.id)->context());verify_layout(session(trial.id)->context(),parts);
    std::string expected;for(const auto& part:parts)expected+=part.text;
    drain_exact(trial.id,expected);require(witness(source.id)==before,"trial changed source");++passed;
  }
  // Five independent whole-literal reconstruction variants from the same original
  // Chinese witnesses. Not chained mixed-state edits or a grapheme UI qualification.
  for(const auto& value:std::vector<std::string>{"e","é","é👩🏽‍💻","é","RAG"}) {
    auto parts=anchors;parts.insert(parts.begin()+1,{Part::literal,value,value,{}});OwnedSession trial;replay(source.id,parts,2048,trial);
    drain_exact(trial.id,anchors[0].text+value+anchors[1].text);++passed;
  }
  {auto parts=anchors;parts.insert(parts.begin()+1,{Part::literal,"RAG","RAG",{}});bool exhausted=false;
   try{OwnedSession trial;replay(source.id,parts,0,trial);}catch(const Failure& f){exhausted=f.code==PG_INCOMPLETE;}
   require(exhausted && witness(source.id)==before,"exhausted replay mutated source");++passed;}
  // A genuinely unconfirmed suffix stays unconfirmed until an actual later selection.
  {OwnedSession partial;create(partial,schema,{},raw);auto ctx=session(partial.id)->context();choose_prefix(ctx,split,"你好",alternate);
   auto parts=observed_prefix(partial.id);require(parts.size()==2 && parts[1].kind==Part::unconfirmed,"suffix unexpectedly confirmed");
   parts.insert(parts.begin()+1,{Part::literal,"👩🏽‍💻","👩🏽‍💻",{}});const auto partialBefore=witness(partial.id);
   OwnedSession trial;replay(partial.id,parts,2048,trial);ctx=session(trial.id)->context();
   const auto selected=choose_prefix(ctx,ctx->input().size(),"世界");
   require(selected.start==split+parts[1].raw.size(),"suffix selection attached to wrong span");
   drain_exact(trial.id,parts[0].text+parts[1].text+selected.text);require(witness(partial.id)==partialBefore,"partial source changed");++passed;}
  std::cout<<"MIXED_NATIVE_PROBE schema="<<schema<<" alternate="<<alternate<<" first_engine_index="<<first.index<<" cases="<<passed<<" actual Chinese selection + explicit literal identity; one drained commit; no host\n";
  return passed;
}
} // namespace mixed_probe

int main(int argc,char** argv) {
  using namespace mixed_probe;
  if(argc!=3){std::cerr<<"usage: mixed-probe verified-shared fresh-owned-user\n";return 2;}
  bool initialized=false;
  try {
    api=rime_get_api();require(api && std::strcmp(api->get_version(),"1.16.0")==0,"wrong engine version");
    RIME_STRUCT(RimeTraits,traits);traits.shared_data_dir=argv[1];traits.user_data_dir=argv[2];
    traits.distribution_name="PAIA authored mixed probe";traits.distribution_code_name="paia_mixed_probe";
    traits.distribution_version="0";traits.app_name="rime.paia_mixed_probe";traits.min_log_level=3;traits.log_dir="";
    api->setup(&traits);api->initialize(&traits);initialized=true;api->deployer_initialize(&traits);
    // Initial native checkpoint qualifies full/Simplified only. Other schemes,
    // interior-unconfirmed edits and real grapheme UI remain explicit later gates.
    const std::string schema="paia_b1_full_ascii",file=std::string(argv[1])+"/"+schema+".schema.yaml";
    require(api->deploy_schema(file.c_str()),"declared probe schema deploy failed");
    const auto start=std::chrono::steady_clock::now();const int total=run(schema,"nihaoshijie",5,false)+run(schema,"nihaoshijie",5,true);
    auto micros=std::chrono::duration_cast<std::chrono::microseconds>(std::chrono::steady_clock::now()-start).count();
    api->finalize();initialized=false;
    std::cout<<"MIXED_NATIVE_PROBE_TOTAL cases="<<total<<" total_us="<<micros<<" ENGINE_NATIVE only; no production path/host integration\n";return 0;
  }catch(const Failure& f){std::cerr<<"MIXED_NATIVE_PROBE_FAILED native_code="<<f.code<<'\n';}
   catch(const std::exception& e){std::cerr<<"MIXED_NATIVE_PROBE_FAILED "<<e.what()<<'\n';}
  if(initialized)api->finalize();return 1;
}

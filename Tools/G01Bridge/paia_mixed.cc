// Included once by paia_g01.cc, sharing its verified engine/helper implementation.
// No Chinese text supplied by Swift can become a proof. Only explicit literal
// spans use an identity candidate. Every converted final value is a real commit.
#include "paia_mixed.h"
#include <rime/translation.h>
#include <limits>
#include <set>
namespace mixed {
struct Proof {std::string raw,text;Code code;};
struct Owner {
  std::string schema;std::map<std::string,bool> options;
  std::unique_ptr<OwnedSession> projection;
  uint64_t generation=0;
  bool sealed=false;
  std::map<uint64_t,Proof> proofs;
  std::vector<Span> rows;
};
std::map<uint64_t,std::unique_ptr<Owner>> owners;
uint64_t nextOwner=0,nextProof=0,nextProjection=0;
Owner& get(uint64_t id){auto i=owners.find(id);if(i==owners.end())throw Failure{PG_INVALID};return *i->second;}
bool valid_utf8(const char *input,size_t count) {
  if(!input || !count || count>4096)return false;
  const auto bytes=reinterpret_cast<const unsigned char*>(input);
  for(size_t i=0;i<count;){
    const unsigned char lead=bytes[i++];if(!lead)return false;if(lead<0x80)continue;
    size_t extra;uint32_t code,minimum;
    if(lead>=0xc2 && lead<=0xdf){extra=1;code=lead&0x1f;minimum=0x80;}
    else if(lead>=0xe0 && lead<=0xef){extra=2;code=lead&0xf;minimum=0x800;}
    else if(lead>=0xf0 && lead<=0xf4){extra=3;code=lead&7;minimum=0x10000;}
    else return false;
    if(extra>count-i)return false;
    for(size_t n=0;n<extra;++n){const auto c=bytes[i++];if((c&0xc0)!=0x80)return false;code=(code<<6)|(c&0x3f);}
    if(code<minimum || code>0x10ffff || (code>=0xd800 && code<=0xdfff))return false;
  }
  return true;
}
bool spelling(const std::string& raw){return !raw.empty() && raw.size()<=4096 && std::all_of(raw.begin(),raw.end(),[](unsigned char c){return (c>='a'&&c<='z')||c=='\'';});}
int open(uint64_t source,uint64_t *out) {
  try {
    if(!out || nextOwner==std::numeric_limits<uint64_t>::max())return PG_INVALID;
    auto s=session(source);if(!s->commit_text().empty())return PG_INVALID;
    char schema[256]={};if(!api->get_current_schema(source,schema,sizeof(schema)))return PG_ENGINE;
    auto owner=std::make_unique<Owner>();owner->schema=schema;owner->options=s->context()->options();
    owner->options["ascii_mode"]=false;owner->options["_no_learning"]=true;owner->options["_auto_commit"]=false;
    auto id=++nextOwner;owners.emplace(id,std::move(owner));*out=id;return PG_OK;
  }catch(const Failure& f){return f.code;}catch(...){return PG_ENGINE;}
}
void close(uint64_t id){owners.erase(id);}
void close_all(){owners.clear();}
int project(uint64_t id,const char *input,size_t inputBytes,size_t limit,PaiaMixedPage *out) {
  try {
    auto& owner=get(id);if(owner.sealed || !input || !out || !limit || limit>2048 || nextProjection==std::numeric_limits<uint64_t>::max())return PG_INVALID;
    if(!valid_utf8(input,inputBytes))return PG_INVALID;
    std::string raw(input,inputBytes);if(!spelling(raw))return PG_INVALID;
    auto trial=std::make_unique<OwnedSession>();create(*trial,owner.schema,owner.options,raw);auto ctx=session(trial->id)->context();
    if(!session(trial->id)->commit_text().empty() || ctx->input()!=raw)return PG_ENGINE;
    std::vector<Span> rows;bool complete=false;
    for(size_t index=0;index<limit;++index) {
      auto c=candidate(ctx,index);if(!c){complete=true;break;}
      if(c->start()!=0 || c->end()==0 || c->end()>raw.size() || candidate_code(c).empty())continue;
      if(rows.size()==64)break;
      rows.emplace_back(c->start(),c->end(),index,c->text(),candidate_code(c));
    }
    fill(&out->result,ctx,rows,complete);out->projection=++nextProjection;
    owner.projection=std::move(trial);owner.rows=std::move(rows);owner.generation=out->projection;return PG_OK;
  }catch(const Failure& f){if(out)free_list(&out->result);return f.code;}catch(...){if(out)free_list(&out->result);return PG_ENGINE;}
}
void free_selection(PaiaMixedSelection *out){if(out){free(out->surface);std::memset(out,0,sizeof(*out));}}
int select(uint64_t id,uint64_t generation,size_t index,PaiaMixedSelection *out) {
  try {
    auto& owner=get(id);
    if(owner.sealed || !out || !owner.projection || owner.generation!=generation || owner.proofs.size()>=256 || nextProof==std::numeric_limits<uint64_t>::max())return PG_INVALID;
    auto row=std::find_if(owner.rows.begin(),owner.rows.end(),[index](const Span& s){return s.index==index;});if(row==owner.rows.end())return PG_INVALID;
    auto src=session(owner.projection->id);auto raw=src->context()->input();
    // A selection runs in its own trial. Rejected/failed choices keep the active
    // projection and previously issued proof tokens intact.
    OwnedSession trial;create(trial,owner.schema,owner.options,raw);auto ctx=session(trial.id)->context();
    auto c=candidate(ctx,index);
    if(!c || c->start()!=row->start || c->end()!=row->end || c->text()!=row->text || !same_code(candidate_code(c),row->code))return PG_CONFLICT;
    if(!ctx->Select(index) || !confirmed(ctx,*row) || !session(trial.id)->commit_text().empty())return PG_ENGINE;
    auto surface=copy(row->text);const auto token=nextProof+1;
    try{owner.proofs.emplace(token,Proof{raw.substr(row->start,row->end-row->start),row->text,row->code});}catch(...){free(surface);throw;}
    nextProof=token;out->proof=token;out->start_utf8=row->start;out->end_utf8=row->end;out->surface=surface;
    // Consume projection capability. A later query gets a fresh generation.
    owner.projection.reset();owner.rows.clear();return PG_OK;
  }catch(const Failure& f){free_selection(out);return f.code;}catch(...){free_selection(out);return PG_ENGINE;}
}
class LiteralIdentity final:public SimpleCandidate {
 public:LiteralIdentity(size_t start,size_t end,const std::string& text):SimpleCandidate("paia_explicit_literal",start,end,text){}
};
void literal(Context *ctx,size_t start,const std::string& text) {
  auto comp=ctx->composition();while(!comp.empty() && comp.back().start>=start)comp.pop_back();
  if((comp.empty()?0:comp.back().end)!=start)throw Failure{PG_CONFLICT};
  for(const auto& seg:comp)if(seg.status<Segment::kSelected)throw Failure{PG_CONFLICT};
  comp.Reset(ctx->input());Segment seg(static_cast<int>(start),static_cast<int>(start+text.size()));
  seg.status=Segment::kSelected;seg.tags.insert("paia_explicit_literal");
  auto translation=New<FifoTranslation>();translation->Append(New<LiteralIdentity>(start,start+text.size(),text));
  seg.menu=New<Menu>();seg.menu->AddTranslation(translation);seg.selected_index=0;
  comp.push_back(std::move(seg));comp.Forward();ctx->set_composition(std::move(comp));ctx->set_caret_pos(ctx->input().size());
}
bool choose_exact(Context *ctx,const Span& span,Budget& budget) {
  if(frontier(ctx)!=span.start || span.code.empty())return false;
  for(size_t index=0;;++index){budget.spend();auto c=candidate(ctx,index);if(!c)return false;
    if(c->start()!=span.start || c->end()!=span.end || c->text()!=span.text || !same_code(candidate_code(c),span.code))continue;
    if(!ctx->Select(index))throw Failure{PG_ENGINE};return confirmed(ctx,span);
  }
}
int commit(uint64_t id,const PaiaMixedPart *parts,size_t count,size_t limit,char **out) {
  try {
    auto& owner=get(id);if(owner.sealed || !out || !parts || !count || count>256 || limit>2048)return PG_INVALID;
    struct Part {std::string raw,text;Code code;bool literal;};std::vector<Part> plan;std::set<uint64_t> seen;
    std::string raw,expected;
    for(size_t i=0;i<count;++i){
      if(!valid_utf8(parts[i].source,parts[i].source_bytes))return PG_INVALID;
      std::string source(parts[i].source,parts[i].source_bytes);
      if(source.empty() || source.size()>4096-raw.size())return PG_INVALID;
      if(parts[i].proof){
        auto p=owner.proofs.find(parts[i].proof);if(p==owner.proofs.end() || !seen.insert(parts[i].proof).second || p->second.raw!=source || p->second.code.empty())return PG_INVALID;
        plan.push_back({source,p->second.text,p->second.code,false});expected+=p->second.text;
      }else{plan.push_back({source,source,{},true});expected+=source;}
      raw+=source;if(expected.size()>65536)return PG_INVALID;
    }
    OwnedSession trial;create(trial,owner.schema,owner.options,raw);auto ctx=session(trial.id)->context();Budget budget{limit};size_t offset=0;
    for(const auto& part:plan){
      if(part.literal){budget.spend();literal(ctx,offset,part.raw);}
      else{ctx->set_caret_pos(offset+part.raw.size());if(!choose_exact(ctx,Span(offset,offset+part.raw.size(),0,part.text,part.code),budget))return PG_CONFLICT;ctx->set_caret_pos(raw.size());}
      offset+=part.raw.size();
    }
    if(ctx->input()!=raw || ctx->composition().input()!=raw || ctx->caret_pos()!=raw.size() || ctx->GetCommitText()!=expected || !session(trial.id)->commit_text().empty())return PG_ENGINE;
    offset=0;
    for(const auto& part:plan){
      bool found=false;
      for(const auto& seg:ctx->composition())if(seg.start==offset && seg.status>=Segment::kSelected){
        auto c=seg.GetSelectedCandidate();if(!c || c->start()!=offset || c->end()!=offset+part.raw.size() || c->text()!=part.text)return PG_CONFLICT;
        if(part.literal ? (c->type()!="paia_explicit_literal") : (c->type()=="paia_explicit_literal" || !same_code(candidate_code(c),part.code)))return PG_CONFLICT;
        found=true;break;
      }
      if(!found)return PG_CONFLICT;offset+=part.raw.size();
    }
    if(!api->commit_composition(trial.id))return PG_ENGINE;
    RimeCommit result{};RIME_STRUCT_INIT(RimeCommit,result);if(!api->get_commit(trial.id,&result))return PG_ENGINE;
    std::string actual;try{actual=result.text?result.text:"";}catch(...){api->free_commit(&result);throw;}api->free_commit(&result);
    RimeCommit again{};RIME_STRUCT_INIT(RimeCommit,again);if(api->get_commit(trial.id,&again)){api->free_commit(&again);return PG_ENGINE;}
    if(actual!=expected)return PG_CONFLICT;*out=copy(actual);owner.sealed=true;owner.projection.reset();owner.rows.clear();return PG_OK;
  }catch(const Failure& f){return f.code;}catch(...){return PG_ENGINE;}
}
void free_text(char *text){free(text);}
void forget(uint64_t id,uint64_t proof){auto i=owners.find(id);if(i!=owners.end())i->second->proofs.erase(proof);}
void free_import(PaiaMixedImport *out){
  if(!out)return;free(out->raw);
  if(out->anchors){for(size_t i=0;i<out->count;++i)free(out->anchors[i].surface);free(out->anchors);}
  std::memset(out,0,sizeof(*out));
}
int adopt(uint64_t id,uint64_t source,PaiaMixedImport *out){
  std::vector<uint64_t> issued;
  try{
    auto& owner=get(id);if(!out || owner.sealed || owner.projection || !owner.proofs.empty())return PG_INVALID;
    auto src=session(source);auto ctx=src->context();if(!src->commit_text().empty())return PG_INVALID;
    char schema[256]={};if(!api->get_current_schema(source,schema,sizeof(schema)) || schema!=owner.schema)return PG_INVALID;
    auto options=ctx->options();options["ascii_mode"]=false;options["_no_learning"]=true;options["_auto_commit"]=false;
    if(options!=owner.options)return PG_INVALID;
    const auto raw=ctx->input();if(!raw.empty() && !spelling(raw))return PG_UNSUPPORTED;
    std::vector<Span> selected;size_t end=0;bool unselected=false;
    for(const auto& segment:ctx->composition()){
      if(segment.start==segment.end)continue;
      if(segment.status<Segment::kSelected){unselected=true;continue;}
      if(unselected)return PG_UNSUPPORTED;
      auto c=segment.GetSelectedCandidate();
      if(!c || c->start()!=end || c->end()<=end || c->end()>raw.size() || candidate_code(c).empty())return PG_UNSUPPORTED;
      selected.emplace_back(c->start(),c->end(),segment.selected_index,c->text(),candidate_code(c));end=c->end();
    }
    if(selected.size()>256 || selected.size()>std::numeric_limits<uint64_t>::max()-nextProof)return PG_INVALID;
    out->raw=copy(raw);out->caret_utf8=ctx->caret_pos();
    if(!selected.empty()){
      out->anchors=static_cast<PaiaMixedSelection*>(std::calloc(selected.size(),sizeof(PaiaMixedSelection)));
      if(!out->anchors)throw std::bad_alloc();out->count=selected.size();
      for(size_t i=0;i<selected.size();++i){
        const auto& span=selected[i];const auto token=++nextProof;issued.push_back(token);
        owner.proofs.emplace(token,Proof{raw.substr(span.start,span.end-span.start),span.text,span.code});
        out->anchors[i]={token,span.start,span.end,copy(span.text)};
      }
    }
    return PG_OK;
  }catch(const Failure& f){for(auto proof:issued)forget(id,proof);free_import(out);return f.code;}
   catch(...){for(auto proof:issued)forget(id,proof);free_import(out);return PG_ENGINE;}
}
PaiaMixedAPI extension={sizeof(PaiaMixedAPI),PAIA_MIXED_ABI,open,close,close_all,project,select,free_selection,commit,free_text,forget,adopt};
}
extern "C" __attribute__((visibility("default"))) PaiaMixedAPI *paia_mixed_get_api(){return &mixed::extension;}

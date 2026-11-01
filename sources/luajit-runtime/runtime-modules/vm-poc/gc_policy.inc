/* Captured scheduler arithmetic, separated from either VM's collector. */
static int gc_settings_valid(const HD2GCSettings *s){
    return s&&isfinite(s->start_growth)&&s->start_growth>=0&&
        isfinite(s->growth_range)&&s->growth_range>0&&
        isfinite(s->full_growth)&&s->full_growth>=0&&
        isfinite(s->min_ms)&&s->min_ms>=0&&isfinite(s->max_ms)&&s->max_ms>=s->min_ms;
}
HD2GCSettings hd2gc_defaults(void){HD2GCSettings s={0.1f,0.5f,1.0f,0.0f,10.0f};return s;}
HD2GCHistory hd2gc_history(void){HD2GCHistory h={0,0,INT32_MAX,INT32_MAX};return h;}
static void gc_cycle(HD2GCHistory *h){h->previous_peak=h->peak;h->previous_floor=h->floor;h->peak=0;h->floor=INT32_MAX;}
int hd2gc_schedule(const HD2GCSettings *s,HD2GCHistory *h,const HD2GCDriver *d,HD2GCReport *r){
    if(!gc_settings_valid(s)||!h||!d||!r||!d->sample||!d->full||!d->step||
       !d->clock.frequency||!d->clock.counter||h->peak<0||h->previous_peak<0||h->floor<0||h->previous_floor<0)return 0;
    HD2GCReport report={0};*r=report;
    if(!d->sample(d->context,&r->total_kb,&r->estimate_kb)||r->total_kb<0||r->estimate_kb<0)return 0;
    if(r->total_kb>h->peak)h->peak=r->total_kb;
    if(r->estimate_kb<h->floor)h->floor=r->estimate_kb;
    int32_t floor=h->floor<h->previous_floor?h->floor:h->previous_floor;
    int32_t peak=h->peak>h->previous_peak?h->peak:h->previous_peak;
    r->growth=(floor?(float)peak/(float)floor:0.0f)-1.0f;
    float excess=r->growth-s->start_growth;
    if(excess>s->full_growth){if(!d->full(d->context))return 0;r->full=1;gc_cycle(h);}
    float alpha=excess/s->growth_range;
    /* Volatile temporaries preserve the captured separate float multiply/add
     * rounding even on compilers/hosts that support fused multiply-add. */
    volatile float low=(1.0f-alpha)*s->min_ms,high=s->max_ms*alpha;
    float budget=low+high;
    if(!isfinite(budget))return 0;
    r->budget_ms=budget>s->max_ms?s->max_ms:budget>s->min_ms?budget:s->min_ms;
    int64_t frequency,start,now;
    if(!d->clock.frequency(d->clock.context,&frequency)||frequency<=0||
       !d->clock.counter(d->clock.context,&start)||start<0)return 0;
    float ticks=(r->budget_ms/1000.0f)*(float)frequency;
    if(!isfinite(ticks)||ticks>=0x1p63f)return 0;
    int64_t duration=(int64_t)ticks;
    if(duration>INT64_MAX-start)return 0;
    int64_t deadline=start+duration,previous=start;
    for(unsigned i=0;i<5000;i++){
        if(i){
            if(!d->clock.counter(d->clock.context,&now)||now<previous)return 0;
            previous=now;if(now>deadline)break;
        }
        int cycle=d->step(d->context);if(cycle<0||cycle>1)return 0;
        r->steps++;if(cycle){r->cycles++;gc_cycle(h);}
    }
    return 1;
}

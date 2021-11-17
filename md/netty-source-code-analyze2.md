> javadoop源码分析系列的笔记，建议查看原文：https://www.javadoop.com/post/netty-part-1。

前文链接：[netty源码分析一](https://orzlinux.cn/blog/netty-source-code-analyze.html)✔️

## 五、Netty的线程池分析

`NioEventLoopGroup` 类和 `NioEventLoop` 继承结构：

![image-20211115185147853](https://gitee.com/hqinglau/img/raw/master/img/20211115185147.png)



我们说的线程池，指的就是`NioEventLoopGroup` 实例，线程池中的单个线程，就是`NioEventLoop`实例。

 在服务端最开始，总是先实例化`NioEventLoopGroup` ：

![image-20211115185511643](https://gitee.com/hqinglau/img/raw/master/img/20211115185511.png)

它的构造方法非常多，其中，参数最全的构造方法为：

```java
public NioEventLoopGroup(int nThreads, Executor executor, EventExecutorChooserFactory chooserFactory,
                         final SelectorProvider selectorProvider,
                         final SelectStrategyFactory selectStrategyFactory,
                         final RejectedExecutionHandler rejectedExecutionHandler,
                         final EventLoopTaskQueueFactory taskQueueFactory) {
    super(nThreads, executor, chooserFactory, selectorProvider, selectStrategyFactory,
            rejectedExecutionHandler, taskQueueFactory);
}
```

参数含义：

- nThreads：线程池中的线程数，也就是 NioEventLoop 的实例数量。
- executor：传一个 executor 实例，它其实不是给线程池用的，而是给 NioEventLoop 用的。
- chooserFactory：当我们提交一个任务到线程池的时候，线程池需要选择（choose）其中的一个线程来执行这个任务，这个就是用来实现选择策略的。
- selectorProvider：这个简单，我们需要通过它来实例化 JDK 的 Selector，可以看到每个线程池都持有一个 selectorProvider 实例。
- selectStrategyFactory：这个涉及到的是线程池中线程的工作流程。
- rejectedExecutionHandler：用于处理线程池中没有可用的线程来执行任务的情况。在 Netty 中这个是给 NioEventLoop 实例用的。

从无参构造开始，到后面的参数，中间设置了一些默认值，例如：

![image-20211115191324654](https://gitee.com/hqinglau/img/raw/master/img/20211115191324.png)

```java
selectorProvider = SelectorProvider.provider();
// 这个没什么好说的，调用了 JDK 提供的方法

selectStrategyFactory = DefaultSelectStrategyFactory.INSTANCE;
//这个涉及到的是线程在做 select 操作和执行任务过程中的策略选择问题，在介绍 NioEventLoop 的时候会用到。 

rejectedExecutionHandler = RejectedExecutionHandlers.reject()
// Netty 选择的默认拒绝策略是：抛出异常
```

源码调用super进入父类：`MultithreadEventLoopGroup`

```java
private static final int DEFAULT_EVENT_LOOP_THREADS;

static {
     DEFAULT_EVENT_LOOP_THREADS = Math.max(1, SystemPropertyUtil.getInt(
                "io.netty.eventLoopThreads", NettyRuntime.availableProcessors() * 2));
}

protected MultithreadEventLoopGroup(int nThreads, ThreadFactory threadFactory, Object... args) {
    super(nThreads == 0 ? DEFAULT_EVENT_LOOP_THREADS : nThreads, threadFactory, args);
}
```

也就是默认线程设置为`CPU核心数*2`。

默认`executor`：

```java
protected MultithreadEventExecutorGroup(int nThreads, ThreadFactory threadFactory, Object... args) {
    this(nThreads, threadFactory == null ? null : new ThreadPerTaskExecutor( threadFactory ), args);
}
```

`ThreadPerTaskExecutor`源码：

```java
public final class ThreadPerTaskExecutor implements Executor {
    private final ThreadFactory threadFactory;

    public ThreadPerTaskExecutor(ThreadFactory threadFactory) {
        this.threadFactory = ObjectUtil.checkNotNull(threadFactory, "threadFactory");
    }

    @Override
    public void execute(Runnable command) {
        threadFactory.newThread(command).start();
    }
}
```

`ThreadPerTaskExecutor`用来对每一个任务新建一个线程。（给NioEventLoop用的）

```java
protected MultithreadEventExecutorGroup(int nThreads, Executor executor, Object... args) {
    this(nThreads, executor, DefaultEventExecutorChooserFactory.INSTANCE, args);
}
```

`DefaultEventExecutorChooserFactory`是线程的选择策略。

```java
@Override
public EventExecutorChooser newChooser(EventExecutor[] executors) {
    if (isPowerOfTwo(executors.length)) {
        return new PowerOfTwoEventExecutorChooser(executors);
    } else {
        return new GenericEventExecutorChooser(executors);
    }
}
```

如果是2的指数：

```java
@Override
public EventExecutor next() {
    return executors[idx.getAndIncrement() & executors.length - 1];
}
```

否则取模：

```java
public EventExecutor next() {
    return executors[(int) Math.abs(idx.getAndIncrement() % executors.length)];
}
```

然后就到了终于有内容的构造方法：

```java
protected MultithreadEventExecutorGroup(int nThreads, Executor executor,
                                        EventExecutorChooserFactory chooserFactory, Object... args) {
    checkPositive(nThreads, "nThreads");
    
	// executor 如果是 null，做一次和前面一样的默认设置。
    if (executor == null) {
        executor = new ThreadPerTaskExecutor(newDefaultThreadFactory());
    }
	// 这里的 children 数组非常重要，它就是线程池中的线程数组，这么说不太严谨，但是就大概这个意思
    children = new EventExecutor[nThreads];
	
    // 下面这个 for 循环将实例化 children 数组中的每一个元素
    for (int i = 0; i < nThreads; i ++) {
        boolean success = false;
        try {
            // 实例化！！！！！！
            children[i] = newChild(executor, args);
            success = true;
        } catch (Exception e) {
            // TODO: Think about if this is a good exception type
            throw new IllegalStateException("failed to create a child event loop", e);
        } finally {
            if (!success) {
                for (int j = 0; j < i; j ++) {
                    children[j].shutdownGracefully();
                }

                for (int j = 0; j < i; j ++) {
                    EventExecutor e = children[j];
                    try {
                        while (!e.isTerminated()) {
                            e.awaitTermination(Integer.MAX_VALUE, TimeUnit.SECONDS);
                        }
                    } catch (InterruptedException interrupted) {
                        // Let the caller handle the interruption.
                        Thread.currentThread().interrupt();
                        break;
                    }
                }
            }
        }
    }

    // ==================== 实例化线程结束 ====================
    
    // 线程选择策略
    chooser = chooserFactory.newChooser(children);
	// 下面的代码逻辑是：给池中每一个线程都设置这个 listener，当监听到所有线程
    // 都 terminate 以后，这个线程池就算真正的 terminate 了。
    final FutureListener<Object> terminationListener = new FutureListener<Object>() {
        @Override
        public void operationComplete(Future<Object> future) throws Exception {
            if (terminatedChildren.incrementAndGet() == children.length) {
                terminationFuture.setSuccess(null);
            }
        }
    };

    for (EventExecutor e: children) {
        e.terminationFuture().addListener(terminationListener);
    }

    Set<EventExecutor> childrenSet = new LinkedHashSet<EventExecutor>(children.length);
    Collections.addAll(childrenSet, children);
    readonlyChildren = Collections.unmodifiableSet(childrenSet);
}
```

其中，`newChild()`用于创建线程池中的线程。它是个抽象方法，在`NioEventLoopGroup`中被覆写了。

```java
@Override
protected EventLoop newChild(Executor executor, Object... args) throws Exception {
    SelectorProvider selectorProvider = (SelectorProvider) args[0];
    SelectStrategyFactory selectStrategyFactory = (SelectStrategyFactory) args[1];
    RejectedExecutionHandler rejectedExecutionHandler = (RejectedExecutionHandler) args[2];
    EventLoopTaskQueueFactory taskQueueFactory = null;
    EventLoopTaskQueueFactory tailTaskQueueFactory = null;

    int argsLength = args.length;
    if (argsLength > 3) {
        taskQueueFactory = (EventLoopTaskQueueFactory) args[3];
    }
    if (argsLength > 4) {
        tailTaskQueueFactory = (EventLoopTaskQueueFactory) args[4];
    }
    return new NioEventLoop(this, executor, selectorProvider,
            selectStrategyFactory.newSelectStrategy(),
            rejectedExecutionHandler, taskQueueFactory, tailTaskQueueFactory);
}
```

最终调用的是`NioEventLoop`的构造方法。

NioEventLoop类属性如下：

```java
private Selector selector;
private Selector unwrappedSelector;
private SelectedSelectionKeySet selectedKeys;

private final SelectorProvider provider; // 有NioEventLoopGroup传进来，一个线程池有一个，用于创建selector实例。

private final SelectStrategy selectStrategy; // select操作的策略

// 这是 IO 任务的执行时间比例，因为每个线程既有 IO 任务执行，
// 也有非 IO 任务需要执行，所以该参数为了保证有足够时间是给 IO 的。
private volatile int ioRatio = 50; 

private int cancelledKeys;
private boolean needsToSelectAgain;
```

每个`NioEventLoop`都有自己的`Selector`。 **Selector是NIO中实现I/O多路复用的关键类。Selector实现了通过一个线程管理多个Channel，从而管理多个网络连接的目的。** 仅用单个线程来处理多个Channels的好处是，只需要更少的线程来处理通道。

`NioEventLoop`调用了父类`SingleThreadEventLoop`的构造方法，它又调用了父类`SingleThreadEventExecutor`的构造方法。

```java
protected SingleThreadEventExecutor(EventExecutorGroup parent, Executor executor,
                                    boolean addTaskWakesUp, int maxPendingTasks,
                                    RejectedExecutionHandler rejectedHandler) {
    // 设置了 parent，也就是之前创建的线程池 NioEventLoopGroup 实例
    super(parent); //this.parent = parent;
    this.addTaskWakesUp = addTaskWakesUp;
    this.maxPendingTasks = Math.max(16, maxPendingTasks);
    
    // 之前实例化的 ThreadPerTaskExecutor
    this.executor = ThreadExecutorMap.apply(executor, this);
    // taskQueue，这个东西很重要，提交给 NioEventLoop 的任务都会进入到这个 taskQueue 中等待被执行
    // 这个 queue 最大16
    taskQueue = newTaskQueue(this.maxPendingTasks);
    // 如果 submit 的任务堆积了到了 16，再往里面提交任务会触发 rejectedExecutionHandler 的执行策略。
    rejectedExecutionHandler = ObjectUtil.checkNotNull(rejectedHandler, "rejectedHandler");
}
```

线程池 `NioEventLoopGroup` 中的每一个线程 `NioEventLoop` 也可以当做一个线程池来用，只不过它只有一个线程。

## 六、Channel的register操作

从EchoClient的`connect()`方法触发，会走到`initAndRegister()`：

```java
final ChannelFuture initAndRegister() {
    Channel channel = null;
    try {
        // 实例化
        channel = channelFactory.newChannel();
        //  init(channel) 方法中，会往 pipeline 中添加 handler
        // （pipeline 此时是 head+channelnitializer+tail）
        init(channel);
    } catch (Throwable t) {
        if (channel != null) {
            channel.unsafe().closeForcibly();

            return new DefaultChannelPromise(channel, GlobalEventExecutor.INSTANCE).setFailure(t);
        }

        return new DefaultChannelPromise(new FailedChannel(), GlobalEventExecutor.INSTANCE).setFailure(t);
    }
    // here==============================
    ChannelFuture regFuture = config().group().register(channel);
    if (regFuture.cause() != null) {
        if (channel.isRegistered()) {
            channel.close();
        } else {
            channel.unsafe().closeForcibly();
        }
    }
    return regFuture;
}
```

该说register这一步了。

```java
ChannelFuture regFuture = config().group().register(channel);
```

上面的 `config().group()` 方法会返回前面实例化的 NioEventLoopGroup 的实例，然后调用其 `register(channel)` 方法。

MultithreadEventLoopGroup

```java
@Override
public EventLoop next() {
    return (EventLoop) super.next(); //源码见下，返回线程池中的一个线程
    // 也就是选择一个NioEventLoop实例
}

//@Override
// public EventExecutor next() {
	//return chooser.next();
//}

@Override
public ChannelFuture register(Channel channel) {
    return next().register(channel);
}
```

其register方法实现在其父类SingleThreadEventLoop中：

```java
@Override
public ChannelFuture register(Channel channel) {
    // 实例化了一个promise
    return register(new DefaultChannelPromise(channel, this));
}

@Override
public ChannelFuture register(final ChannelPromise promise) {
    ObjectUtil.checkNotNull(promise, "promise");
    // channel持有Unsafe实例，register操作封装在unsafe中
    promise.channel().unsafe().register(this, promise);
    return promise;
}
```

AbstractChannel # AbstractUnsafe

```java
@Override
public final void register(EventLoop eventLoop, final ChannelPromise promise) {
    。。。

    // 将eventLoop实例设置给这个Channel
    // 后续这个channel所有的异步操作，都要提交给这个eventLoop执行
    AbstractChannel.this.eventLoop = eventLoop;

    // 如果发起 register 动作的线程就是 eventLoop 实例中的线程，那么
    // 直接调用 register0(promise)
    //     @Override
    //public boolean inEventLoop(Thread thread) {
    //    return thread == this.thread;
    //}
    // 第一次register的时候是main线程，然后这个时候NioEventLoop绑定的thread还为空
    // 所以这句thread == this.thread为false
    if (eventLoop.inEventLoop()) {
        register0(promise);
    } else {
        try {
            // 否则，提交任务给 eventLoop，eventLoop 中
            // 的线程会负责调用 register0(promise)
            eventLoop.execute(new Runnable() {
                @Override
                public void run() {
                    register0(promise);
                }
            });
        } catch (Throwable t) {
            。。。
        }
    }
}
```

`register` 操作，其实提交到 `eventLoop` 以后，就直接返回 `promise` 实例了，剩下的`register0` 是异步操作，它由 `NioEventLoop` 实例来完成。

> Channel 实例一旦 register 到了 NioEventLoopGroup 实例中的某个 NioEventLoop 实例，那么后续该 Channel 的所有操作，都是由该 NioEventLoop 实例来完成的。
>
> 这个也非常简单，因为 Selector 实例是在 NioEventLoop 实例中的，Channel 实例一旦注册到某个 Selector 实例中，当然也只能在这个实例中处理 NIO 事件。

## 七、NioEventLoop 工作流程

在分析线程池的实例化的时候说过，`NioEventLoop` 中并没有启动 Java 线程。`register` 过程中调用的 **eventLoop.execute(runnable)** 这个方法，这个代码在父类 `SingleThreadEventExecutor` 中：

```java
private void execute(Runnable task, boolean immediate) {
    boolean inEventLoop = inEventLoop();
    // 添加任务到之前介绍的 taskQueue 中，
    // 如果 taskQueue 满了(默认大小 16)，根据我们之前说的，默认的策略是抛出异常
    addTask(task);
    
    // 判断添加任务的线程是否就是当前 EventLoop 中的线程
    if (!inEventLoop) {
        // 如果不是 NioEventLoop 内部线程提交的 task，那么判断下线程是否已经启动，没有的话，就启动线程
        startThread();
        if (isShutdown()) {
            boolean reject = false;
            try {
                if (removeTask(task)) {
                    reject = true;
                }
            } catch (UnsupportedOperationException e) {
               
            }
            if (reject) {
                reject();
            }
        }
    }
    if (!addTaskWakesUp && immediate) {
        wakeup(inEventLoop);
    }
}
```

startThread源码：

```java
private void startThread() {
    if (state == ST_NOT_STARTED) {
        if (STATE_UPDATER.compareAndSet(this, ST_NOT_STARTED, ST_STARTED)) {
            boolean success = false;
            try {
                doStartThread();
                success = true;
            } finally {
                if (!success) {
                    STATE_UPDATER.compareAndSet(this, ST_STARTED, ST_NOT_STARTED);
                }
            }
        }
    }
}
```

如果线程没有启动：

```java
private void doStartThread() {
    assert thread == null;
    // executor就是一开始我们实例化 NioEventLoop 的时候传进来的 
    // ThreadPerTaskExecutor 的实例。它是每次来一个任务，创建一个线程的那种 executor。
    // 一旦我们调用它的 execute 方法，它就会创建一个新的线程，所以这里终于会创建 Thread 实例
    executor.execute(new Runnable() {
        @Override
        public void run() {
            thread = Thread.currentThread();
            if (interrupted) {
                thread.interrupt();
            }

            boolean success = false;
            updateLastExecutionTime();
            try {
                SingleThreadEventExecutor.this.run();
                success = true;
            } catch (Throwable t) {
                logger.warn("Unexpected exception from an event executor: ", t);
            } finally {
                。。。
            }
        }
    });
}
```

上面线程启动以后，会执行 NioEventLoop 中的 `run()` 方法，这是一个**非常重要**的方法，这个方法肯定是没那么容易结束的，必然是像 JDK 线程池的 Worker 那样，不断地循环获取新的任务的。它需要不断地做 select 操作和轮询 taskQueue 这个队列。

> 前面在 register 的时候提交了 register 任务给 NioEventLoop，这是 NioEventLoop 接收到的第一个任务，所以这里会实例化 Thread 并且启动，然后进入到 NioEventLoop 中的 run 方法。实际情况可能是，Channel 实例被 register 到一个已经启动线程的 NioEventLoop 实例中。
>
> ```java
> ChannelFuture regFuture = config().group().register(channel);
> ```

## 八、回到 Channel 的 register 操作

AbstractChannel

```java
private void register0(ChannelPromise promise) {
    try {
        if (!promise.setUncancellable() || !ensureOpen(promise)) {
            return;
        }
        boolean firstRegistration = neverRegistered;
        // 进行 JDK 底层的操作：Channel 注册到 Selector 上
        doRegister();
        neverRegistered = false;
        registered = true;

        pipeline.invokeHandlerAddedIfNeeded();

        // 设置当前 promise 的状态为 success
        // 因为当前 register 方法是在 eventLoop 中的线程中执行的，需要通知提交 register 操作的线程
        safeSetSuccess(promise);
        pipeline.fireChannelRegistered();
        // 如果channel已经打开
        if (isActive()) {
            if (firstRegistration) {
                pipeline.fireChannelActive();
            } else if (config().isAutoRead()) {
                beginRead();
            }
        }
    } catch (Throwable t) {
        。。。
    }
}
```

AbstractNioChannel##doRegister

```java
protected void doRegister() throws Exception {
    boolean selected = false;
    for (;;) {
        try {
            //public abstract SelectionKey register(Selector sel, int ops, Object att)
            selectionKey = javaChannel().register(eventLoop().unwrappedSelector(), 0, this);
            return;
        } catch (CancelledKeyException e) {
            。。。
        }
    }
}
```

这里做了 JDK 底层的 register 操作，将 SocketChannel(或 ServerSocketChannel) 注册到 Selector 中，并且可以看到，这里的监听集合设置为了 **0**，也就是什么都不监听。

之前pipeline样子：

![image-20211116123759789](https://gitee.com/hqinglau/img/raw/master/img/20211116123759.png)

```java
pipeline.invokeHandlerAddedIfNeeded();
```

会执行到：

```java
public void handlerAdded(ChannelHandlerContext ctx) throws Exception {
    if (ctx.channel().isRegistered()) {
        if (initChannel(ctx)) {
            removeState(ctx);
        }
    }
}
```

initChannel中：

```java
private boolean initChannel(ChannelHandlerContext ctx) throws Exception {
    if (initMap.add(ctx)) { // Guard against re-entrance.
        try {
            // 1. 将把我们自定义的 handlers 添加到 pipeline 中
            initChannel((C) ctx.channel());
        } catch (Throwable cause) {
            exceptionCaught(ctx, cause);
        } finally {
            // 2. 将 ChannelInitializer 实例从 pipeline 中删除
            ChannelPipeline pipeline = ctx.pipeline();
            if (pipeline.context(this) != null) {
                pipeline.remove(this);
            }
        }
        return true;
    }
    return false;
}
```

![image-20211116124821343](https://gitee.com/hqinglau/img/raw/master/img/20211116124821.png)

![image-20211116125857436](https://gitee.com/hqinglau/img/raw/master/img/20211116125857.png)

> 总之就是从 head 中开始，依次往下寻找所有 Inbound handler，执行其 channelRegistered(ctx) 操作。


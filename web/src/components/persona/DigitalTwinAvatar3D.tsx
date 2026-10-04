"use client";

import { useEffect, useRef, useState } from "react";
import * as THREE from "three";
import { GLTFLoader } from "three/examples/jsm/loaders/GLTFLoader.js";

export type PersonaDimension = "brain" | "communication" | "tech" | "execution" | "all";

interface DigitalTwinAvatar3DProps {
  activeDimension: PersonaDimension;
  onSelectDimension: (dim: PersonaDimension) => void;
  ruleStats?: {
    ironLaws: number;
    communication: number;
    tech: number;
    execution: number;
  };
  className?: string;
}

export default function DigitalTwinAvatar3D({
  activeDimension,
  onSelectDimension,
  ruleStats = { ironLaws: 6, communication: 3, tech: 8, execution: 5 },
  className = "",
}: DigitalTwinAvatar3DProps) {
  const containerRef = useRef<HTMLDivElement>(null);
  const [isRotating, setIsRotating] = useState(false);
  const [isLoading, setIsLoading] = useState(true);
  const [currentActionName, setCurrentActionName] = useState<"idle" | "agree">("idle");

  // Animation & Three.js references (No React setState in 60fps loop!)
  const mixerRef = useRef<THREE.AnimationMixer | null>(null);
  const actionsRef = useRef<Record<string, THREE.AnimationAction>>({});
  const realAvatarRef = useRef<THREE.Group | null>(null);
  const bonesMapRef = useRef<Record<string, THREE.Object3D>>({});
  const haloMeshRef = useRef<THREE.Mesh | null>(null);
  const coreMeshRef = useRef<THREE.Mesh | null>(null);

  useEffect(() => {
    const container = containerRef.current;
    if (!container) return;

    const width = container.clientWidth || 480;
    const height = container.clientHeight || 560;

    // 1. Scene & Camera Setup (Optimized Position for Human Portrait)
    const scene = new THREE.Scene();
    const camera = new THREE.PerspectiveCamera(38, width / height, 0.1, 100);
    // Focus squarely on chest and head without cutting off face
    camera.position.set(0, 1.48, 2.7);

    // 2. High-Performance WebGL Renderer (No heavy shadow maps, locked pixel ratio)
    const renderer = new THREE.WebGLRenderer({
      antialias: true,
      alpha: true,
      powerPreference: "high-performance",
    });
    renderer.setSize(width, height);
    renderer.setPixelRatio(Math.min(window.devicePixelRatio, 1.5));
    renderer.toneMapping = THREE.ACESFilmicToneMapping;
    renderer.toneMappingExposure = 1.25;
    container.appendChild(renderer.domElement);

    // 3. Studio Portrait Lighting
    const ambientLight = new THREE.AmbientLight(0xffffff, 1.2);
    scene.add(ambientLight);

    // Soft front key light
    const keyLight = new THREE.DirectionalLight(0xfff7ee, 1.8);
    keyLight.position.set(1.2, 2.8, 2.5);
    scene.add(keyLight);

    // Cyberpunk rim accents
    const rimPurple = new THREE.PointLight(0xa855f7, 2.4, 8);
    rimPurple.position.set(-2, 2.2, -1.2);
    scene.add(rimPurple);

    const rimCyan = new THREE.PointLight(0x06b6d4, 1.8, 8);
    rimCyan.position.set(2, 1.2, 1.5);
    scene.add(rimCyan);

    // Humanoid Root Group
    const avatarGroup = new THREE.Group();
    // Position model so head & chest sit comfortably in visual center
    avatarGroup.position.set(0, -0.85, 0);
    scene.add(avatarGroup);

    // Elegant Halo ABOVE the head (Never over face)
    const haloGeo = new THREE.TorusGeometry(0.16, 0.008, 16, 64);
    const haloMat = new THREE.MeshBasicMaterial({
      color: 0xa855f7,
      transparent: true,
      opacity: 0.8,
    });
    const haloMesh = new THREE.Mesh(haloGeo, haloMat);
    haloMesh.rotation.x = Math.PI / 2;
    haloMesh.position.set(0, 1.95, 0);
    avatarGroup.add(haloMesh);
    haloMeshRef.current = haloMesh;

    // Tech Core Micro-gem in chest (very small, subtle inside chest)
    const coreGeo = new THREE.OctahedronGeometry(0.04, 1);
    const coreMat = new THREE.MeshBasicMaterial({
      color: 0xf59e0b,
      transparent: true,
      opacity: 0.75,
    });
    const coreMesh = new THREE.Mesh(coreGeo, coreMat);
    coreMesh.position.set(0, 1.35, 0.12);
    avatarGroup.add(coreMesh);
    coreMeshRef.current = coreMesh;

    // Ambient floating particles (GPU transformed, zero CPU overhead)
    const particleCount = 200;
    const particleGeo = new THREE.BufferGeometry();
    const particlePositions = new Float32Array(particleCount * 3);
    for (let i = 0; i < particleCount * 3; i += 3) {
      particlePositions[i] = (Math.random() - 0.5) * 3;
      particlePositions[i + 1] = Math.random() * 2.5;
      particlePositions[i + 2] = (Math.random() - 0.5) * 3;
    }
    particleGeo.setAttribute("position", new THREE.BufferAttribute(particlePositions, 3));
    const particleMat = new THREE.PointsMaterial({
      color: 0xa855f7,
      size: 0.02,
      transparent: true,
      opacity: 0.4,
      blending: THREE.AdditiveBlending,
    });
    const particles = new THREE.Points(particleGeo, particleMat);
    avatarGroup.add(particles);

    // 4. Load Real-Human Avatar & Animation
    const loader = new GLTFLoader();

    Promise.all([
      loader.loadAsync("/models/avatar_real.glb").catch(() => null),
      loader.loadAsync("/models/human.glb").catch(() => null),
    ]).then(([realGltf, animGltf]) => {
      setIsLoading(false);

      if (realGltf && realGltf.scene) {
        const model = realGltf.scene;
        model.scale.set(1.05, 1.05, 1.05);
        avatarGroup.add(model);
        realAvatarRef.current = model;

        const bones: Record<string, THREE.Object3D> = {};
        model.traverse((child) => {
          if (child instanceof THREE.Bone) {
            bones[child.name] = child;
          }
          if (child instanceof THREE.Mesh) {
            // Keep real human face & hair 100% clean and visible
            if (child.material) {
              child.material.side = THREE.FrontSide;
              if ("roughness" in child.material) {
                child.material.roughness = Math.max(0.35, child.material.roughness * 0.95);
              }
            }
          }
        });
        bonesMapRef.current = bones;

        // Parent halo to Head bone above hair
        if (bones.Head) {
          bones.Head.add(haloMesh);
          haloMesh.position.set(0, 0.26, 0); // Position safely ABOVE hair
        }
        if (bones.Spine2) {
          bones.Spine2.add(coreMesh);
          coreMesh.position.set(0, 0.1, 0.1);
        }

        // Apply Natural Idle Animations from animGltf
        if (animGltf && animGltf.animations && animGltf.animations.length > 0) {
          const mixer = new THREE.AnimationMixer(model);
          mixerRef.current = mixer;

          const idleClip = animGltf.animations.find((a) => a.name.toLowerCase().includes("idle"));
          const agreeClip = animGltf.animations.find((a) => a.name.toLowerCase().includes("agree"));

          if (idleClip) {
            const clonedIdle = idleClip.clone();
            clonedIdle.tracks.forEach((track) => {
              track.name = track.name.replace(/^mixamorig:/, "");
            });
            const idleAction = mixer.clipAction(clonedIdle);
            idleAction.setEffectiveTimeScale(0.85); // Lifelike slow breathing
            idleAction.play();
            actionsRef.current.idle = idleAction;
          }

          if (agreeClip) {
            const clonedAgree = agreeClip.clone();
            clonedAgree.tracks.forEach((track) => {
              track.name = track.name.replace(/^mixamorig:/, "");
            });
            const agreeAction = mixer.clipAction(clonedAgree);
            agreeAction.loop = THREE.LoopOnce;
            agreeAction.clampWhenFinished = false;
            actionsRef.current.agree = agreeAction;
          }
        }
      }
    });

    // 5. Drag to rotate model
    let isDragging = false;
    let prevMouseX = 0;

    const handlePointerDown = (e: MouseEvent) => {
      isDragging = true;
      prevMouseX = e.clientX;
    };

    const handlePointerUp = () => {
      isDragging = false;
    };

    const handlePointerMove = (e: MouseEvent) => {
      if (isDragging) {
        const deltaX = e.clientX - prevMouseX;
        avatarGroup.rotation.y += deltaX * 0.008;
        prevMouseX = e.clientX;
      }
    };

    container.addEventListener("mousedown", handlePointerDown);
    window.addEventListener("mouseup", handlePointerUp);
    container.addEventListener("mousemove", handlePointerMove);

    // 6. Smooth 60fps Animation Loop (Zero React State calls!)
    let animId: number;
    const clock = new THREE.Clock();

    const animate = () => {
      animId = requestAnimationFrame(animate);
      const delta = clock.getDelta();
      const elapsed = clock.getElapsedTime();

      // Skeletal mixer update
      if (mixerRef.current) {
        mixerRef.current.update(delta);
      }

      // Auto rotation if enabled
      if (isRotating) {
        avatarGroup.rotation.y += 0.004;
      }

      // Gentle ambient particle rotation (Pure GPU matrix transform)
      particles.rotation.y = elapsed * 0.03;

      // Halo breathing pulse (above head)
      if (haloMeshRef.current) {
        const scale = 1 + Math.sin(elapsed * 2.5) * 0.08;
        haloMeshRef.current.scale.set(scale, scale, scale);
        haloMeshRef.current.rotation.z = elapsed * 0.5;
      }

      // Core pulse
      if (coreMeshRef.current) {
        coreMeshRef.current.rotation.x = elapsed * 1.5;
        coreMeshRef.current.rotation.y = elapsed * 2.0;
      }

      renderer.render(scene, camera);
    };

    animate();

    // 7. Resize Observer
    const handleResize = () => {
      if (!container || !renderer || !camera) return;
      const newW = container.clientWidth;
      const newH = container.clientHeight;
      camera.aspect = newW / newH;
      camera.updateProjectionMatrix();
      renderer.setSize(newW, newH);
    };

    const resizeObserver = new ResizeObserver(handleResize);
    resizeObserver.observe(container);

    return () => {
      cancelAnimationFrame(animId);
      resizeObserver.disconnect();
      container.removeEventListener("mousedown", handlePointerDown);
      window.removeEventListener("mouseup", handlePointerUp);
      container.removeEventListener("mousemove", handlePointerMove);
      if (renderer.domElement && container.contains(renderer.domElement)) {
        container.removeChild(renderer.domElement);
      }
      renderer.dispose();
    };
  }, [isRotating]);

  // Trigger Agree nodding animation
  const triggerAgreeAction = () => {
    const agree = actionsRef.current.agree;
    const idle = actionsRef.current.idle;
    if (agree) {
      agree.reset();
      agree.fadeIn(0.2);
      agree.play();
      setCurrentActionName("agree");
      setTimeout(() => {
        if (idle) idle.fadeIn(0.3);
        setCurrentActionName("idle");
      }, 1800);
    }
  };

  const LEFT_DIMENSIONS = [
    {
      id: "brain" as const,
      label: "脑核 · 绝对红线",
      color: "#EF4444",
      bgRgba: "rgba(239, 68, 68, 0.18)",
      borderRgba: "rgba(239, 68, 68, 0.45)",
      count: ruleStats.ironLaws,
      tag: "Cognitive Law",
      desc: "严守铁律、先查官方、不回滚",
    },
    {
      id: "tech" as const,
      label: "心核 · 技术与架构",
      color: "#F59E0B",
      bgRgba: "rgba(245, 158, 11, 0.18)",
      borderRgba: "rgba(245, 158, 11, 0.45)",
      count: ruleStats.tech,
      tag: "Tech Philosophy",
      desc: "高性能流式、容器化K8s、本地优先",
    },
  ];

  const RIGHT_DIMENSIONS = [
    {
      id: "communication" as const,
      label: "喉核 · 交互与沟通",
      color: "#06B6D4",
      bgRgba: "rgba(6, 182, 212, 0.18)",
      borderRgba: "rgba(6, 182, 212, 0.45)",
      count: ruleStats.communication,
      tag: "Vocal Tone",
      desc: "直给结论、无废话、1)2)3)编号",
    },
    {
      id: "execution" as const,
      label: "肢端 · 工作与执行",
      color: "#10B981",
      bgRgba: "rgba(16, 185, 129, 0.18)",
      borderRgba: "rgba(16, 185, 129, 0.45)",
      count: ruleStats.execution,
      tag: "Autonomous Act",
      desc: "自主推进做完、数据校验闭环",
    },
  ];

  return (
    <div
      className={`relative w-full h-full min-h-[520px] rounded-3xl overflow-hidden select-none border border-[var(--aurora-border)] bg-gradient-to-b from-[#0c0d18] via-[#090a12] to-[#05060b] shadow-2xl ${className}`}
    >
      {/* 3D WebGL Canvas (Human Model In Full Display) */}
      <div ref={containerRef} className="w-full h-full cursor-grab active:cursor-grabbing" />

      {/* Loading Skeleton */}
      {isLoading && (
        <div className="absolute inset-0 bg-[#090a12]/90 backdrop-blur-md flex flex-col items-center justify-center gap-3 z-30 pointer-events-none">
          <div className="w-10 h-10 rounded-2xl border-2 border-transparent border-t-[#A855F7] animate-spin flex items-center justify-center bg-[#A855F7]/10" />
          <div className="text-xs font-mono text-[#A855F7] tracking-wider animate-pulse">
            LOADING REAL-HUMAN TWIN...
          </div>
          <span className="text-[11px] text-[var(--aurora-fg4)]">
            正在载入写实真人面貌与呼吸动作
          </span>
        </div>
      )}

      {/* Top Holographic Header Bar */}
      <div className="absolute top-3 left-3 right-3 flex items-center justify-between pointer-events-none z-10">
        <div className="flex items-center gap-2 bg-black/50 backdrop-blur-md px-3 py-1 rounded-full border border-white/10 shadow-lg">
          <div className="w-2 h-2 rounded-full bg-[#10B981] animate-ping" />
          <span className="text-[11px] font-mono text-white/90 font-medium tracking-wide">
            REAL HUMAN DIGITAL TWIN · ONLINE
          </span>
        </div>

        <div className="flex items-center gap-1.5 pointer-events-auto">
          {/* Nod Action Button */}
          <button
            onClick={triggerAgreeAction}
            className="px-2.5 py-1 rounded-xl text-[11px] font-mono font-medium transition-all bg-black/50 border border-white/10 text-white/80 hover:text-white hover:bg-white/15 flex items-center gap-1 backdrop-blur-md"
            title="触发点头赞同真人动画"
          >
            <span>点头回应</span>
            {currentActionName === "agree" && <span className="w-1.5 h-1.5 rounded-full bg-[#10B981]" />}
          </button>

          {/* Auto Rotation Toggle */}
          <button
            onClick={() => setIsRotating((v) => !v)}
            className={`px-2.5 py-1 rounded-xl text-[11px] font-mono font-medium transition-all backdrop-blur-md border ${
              isRotating
                ? "bg-[#A855F7]/25 text-[#A855F7] border-[#A855F7]/50"
                : "bg-black/50 text-white/70 border-white/10 hover:bg-white/10"
            }`}
          >
            {isRotating ? "自转中" : "暂停自转"}
          </button>
        </div>
      </div>

      {/* Left Wing Cyber Dock (Never Covers Face - Anchored to Left Screen Edge) */}
      <div className="absolute left-3 top-1/2 -translate-y-1/2 flex flex-col gap-2.5 z-20 pointer-events-auto max-w-[170px]">
        {LEFT_DIMENSIONS.map((dim) => {
          const isSelected = activeDimension === dim.id;
          return (
            <div
              key={dim.id}
              onClick={() => onSelectDimension(dim.id)}
              className={`group cursor-pointer p-2.5 rounded-2xl backdrop-blur-xl border transition-all duration-200 flex flex-col gap-1 shadow-lg ${
                isSelected
                  ? "scale-105 shadow-2xl ring-1"
                  : "opacity-80 hover:opacity-100 hover:scale-102"
              }`}
              style={{
                backgroundColor: isSelected ? dim.bgRgba : "rgba(12, 14, 22, 0.75)",
                borderColor: isSelected ? dim.color : dim.borderRgba,
                boxShadow: isSelected ? `0 8px 24px -4px ${dim.color}40` : undefined,
              }}
            >
              <div className="flex items-center justify-between">
                <div className="flex items-center gap-1.5">
                  <div className="w-2 h-2 rounded-full" style={{ backgroundColor: dim.color }} />
                  <span className="text-xs font-bold text-white tracking-tight">
                    {dim.label}
                  </span>
                </div>
                <span
                  className="text-[10px] font-mono px-1.5 py-0.2 rounded-full font-bold"
                  style={{ backgroundColor: `${dim.color}25`, color: dim.color }}
                >
                  {dim.count}
                </span>
              </div>
              <span className="text-[10px] text-white/50 leading-tight">
                {dim.desc}
              </span>
            </div>
          );
        })}
      </div>

      {/* Right Wing Cyber Dock (Never Covers Face - Anchored to Right Screen Edge) */}
      <div className="absolute right-3 top-1/2 -translate-y-1/2 flex flex-col gap-2.5 z-20 pointer-events-auto max-w-[170px]">
        {RIGHT_DIMENSIONS.map((dim) => {
          const isSelected = activeDimension === dim.id;
          return (
            <div
              key={dim.id}
              onClick={() => onSelectDimension(dim.id)}
              className={`group cursor-pointer p-2.5 rounded-2xl backdrop-blur-xl border transition-all duration-200 flex flex-col gap-1 shadow-lg ${
                isSelected
                  ? "scale-105 shadow-2xl ring-1"
                  : "opacity-80 hover:opacity-100 hover:scale-102"
              }`}
              style={{
                backgroundColor: isSelected ? dim.bgRgba : "rgba(12, 14, 22, 0.75)",
                borderColor: isSelected ? dim.color : dim.borderRgba,
                boxShadow: isSelected ? `0 8px 24px -4px ${dim.color}40` : undefined,
              }}
            >
              <div className="flex items-center justify-between">
                <div className="flex items-center gap-1.5">
                  <div className="w-2 h-2 rounded-full" style={{ backgroundColor: dim.color }} />
                  <span className="text-xs font-bold text-white tracking-tight">
                    {dim.label}
                  </span>
                </div>
                <span
                  className="text-[10px] font-mono px-1.5 py-0.2 rounded-full font-bold"
                  style={{ backgroundColor: `${dim.color}25`, color: dim.color }}
                >
                  {dim.count}
                </span>
              </div>
              <span className="text-[10px] text-white/50 leading-tight">
                {dim.desc}
              </span>
            </div>
          );
        })}
      </div>

      {/* Bottom Dimension Selector Bar */}
      <div className="absolute bottom-2.5 left-3 right-3 flex items-center justify-center gap-1.5 z-20 pointer-events-auto overflow-x-auto scrollbar-none py-1">
        <button
          onClick={() => onSelectDimension("all")}
          className={`px-3 py-1 rounded-xl text-xs font-medium transition-all shrink-0 backdrop-blur-md border ${
            activeDimension === "all"
              ? "bg-[#8B5CF6] text-white border-[#8B5CF6] shadow-lg font-semibold"
              : "bg-black/50 text-white/70 border-white/10 hover:text-white hover:bg-black/70"
          }`}
        >
          🌐 全景视野
        </button>

        {[...LEFT_DIMENSIONS, ...RIGHT_DIMENSIONS].map((dim) => {
          const isSelected = activeDimension === dim.id;
          return (
            <button
              key={dim.id}
              onClick={() => onSelectDimension(dim.id)}
              className={`px-2.5 py-1 rounded-xl text-xs font-medium transition-all shrink-0 backdrop-blur-md border flex items-center gap-1 ${
                isSelected
                  ? "text-white shadow-lg font-semibold scale-102"
                  : "bg-black/50 text-white/70 border-white/10 hover:text-white hover:bg-black/70"
              }`}
              style={{
                backgroundColor: isSelected ? dim.color : undefined,
                borderColor: isSelected ? dim.color : undefined,
              }}
            >
              <span>{dim.label.split(" · ")[0]}</span>
              <span className="text-[10px] px-1 rounded-full bg-black/25">
                {dim.count}
              </span>
            </button>
          );
        })}
      </div>
    </div>
  );
}
